#include <jni.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>
#include <sys/socket.h>
#include <sys/select.h>
#include <sys/ioctl.h>
#include <linux/usbdevice_fs.h>
#include <netinet/in.h>
#include <arpa/inet.h>

#include "rtl-sdr.h"

JNIEXPORT void JNICALL
Java_org_noxylva_lbjconsole_flutter_LbjUsbNative_nativeStop(JNIEnv *env, jclass cls);

int lbj_pluto_running(void);
int lbj_pluto_exit_error(void);
int lbj_pluto_stage(void);
void lbj_pluto_stop(void);

#define LBJ_PORT 14423
#define LBJ_FREQ_HZ 821237500
#define LBJ_RATE_HZ 240000

static struct {
	pthread_mutex_t lock;
	pthread_cond_t started_cond;
	pthread_t thread;
	rtlsdr_dev_t *dev;
	int running;
	int stop;
	int started;
	int start_err;
	int exit_err;
	int listen_fd;
	int client_fd;
	int send_failed;
	int finished;
	int stage;
} S = {
	PTHREAD_MUTEX_INITIALIZER, PTHREAD_COND_INITIALIZER,
	0, NULL, 0, 0, 0, 0, 0, -1, -1, 0, 0,
};

struct command {
	unsigned char cmd;
	unsigned int param;
} __attribute__((packed));

static int set_gain_by_index(rtlsdr_dev_t *dev, unsigned int index)
{
	int res = 0;
	int *gains;
	int count = rtlsdr_get_tuner_gains(dev, NULL);

	if (count > 0 && (unsigned int)count > index) {
		gains = malloc(sizeof(int) * count);
		count = rtlsdr_get_tuner_gains(dev, gains);
		res = rtlsdr_set_tuner_gain(dev, gains[index]);
		free(gains);
	}
	return res;
}

static void apply_command(rtlsdr_dev_t *dev, struct command *cmd)
{
	uint32_t param = ntohl(cmd->param);
	uint32_t tmp;

	switch (cmd->cmd) {
	case 0x01: rtlsdr_set_center_freq(dev, param); break;
	case 0x02: rtlsdr_set_sample_rate(dev, param); break;
	case 0x03: rtlsdr_set_tuner_gain_mode(dev, (int)param); break;
	case 0x04: rtlsdr_set_tuner_gain(dev, (int)param); break;
	case 0x05: rtlsdr_set_freq_correction(dev, (int)param); break;
	case 0x06:
		tmp = param;
		rtlsdr_set_tuner_if_gain(dev, (int)(tmp >> 16), (short)(tmp & 0xffff));
		break;
	case 0x07: rtlsdr_set_testmode(dev, (int)param); break;
	case 0x08: rtlsdr_set_agc_mode(dev, (int)param); break;
	case 0x09: rtlsdr_set_direct_sampling(dev, (int)param); break;
	case 0x0a: rtlsdr_set_offset_tuning(dev, (int)param); break;
	case 0x0b: rtlsdr_set_xtal_freq(dev, param, 0); break;
	case 0x0c: rtlsdr_set_xtal_freq(dev, 0, param); break;
	case 0x0d: set_gain_by_index(dev, param); break;
	case 0x0e: rtlsdr_set_bias_tee(dev, (int)param); break;
	default: break;
	}
}

static void *command_main(void *arg)
{
	rtlsdr_dev_t *dev = S.dev;
	int fd = S.client_fd;

	while (!S.stop) {
		struct command cmd;
		size_t got = 0;
		while (got < sizeof(cmd) && !S.stop) {
			fd_set rfds;
			struct timeval tv;
			FD_ZERO(&rfds);
			FD_SET(fd, &rfds);
			tv.tv_sec = 0;
			tv.tv_usec = 200000;
			if (select(fd + 1, &rfds, NULL, NULL, &tv) <= 0)
				continue;
			ssize_t n = recv(fd, (char *)&cmd + got, sizeof(cmd) - got, 0);
			if (n <= 0) {
				S.send_failed = 1;
				rtlsdr_cancel_async(dev);
				return NULL;
			}
			got += (size_t)n;
		}
		if (S.stop)
			return NULL;
		apply_command(dev, &cmd);
	}
	return NULL;
}

static void stream_cb(unsigned char *buf, uint32_t len, void *ctx)
{
	(void)ctx;
	uint32_t off = 0;
	while (off < len) {
		ssize_t n = send(S.client_fd, buf + off, len - off, MSG_NOSIGNAL);
		if (n <= 0) {
			S.send_failed = 1;
			rtlsdr_cancel_async(S.dev);
			return;
		}
		off += (uint32_t)n;
	}
	if (S.stop)
		rtlsdr_cancel_async(S.dev);
}

static void signal_started(int err)
{
	pthread_mutex_lock(&S.lock);
	S.start_err = err;
	S.started = 1;
	pthread_cond_signal(&S.started_cond);
	pthread_mutex_unlock(&S.lock);
}

static void *session_main(void *arg)
{
	int fd = (int)(intptr_t)arg;
	rtlsdr_dev_t *dev = NULL;
	int r;

	S.stage = 1;
	r = rtlsdr_open_fd(&dev, fd);
	if (r < 0) {
		signal_started(r);
		S.stage = 0;
		S.finished = 1;
		return NULL;
	}
	S.dev = dev;

	S.stage = 2;
	rtlsdr_set_sample_rate(dev, LBJ_RATE_HZ);
	rtlsdr_set_center_freq(dev, LBJ_FREQ_HZ);
	rtlsdr_reset_buffer(dev);

	S.stage = 3;
	int lfd = socket(AF_INET, SOCK_STREAM, 0);
	if (lfd < 0) {
		signal_started(-1000);
		goto out_dev;
	}
	int on = 1;
	setsockopt(lfd, SOL_SOCKET, SO_REUSEADDR, &on, sizeof(on));
	struct sockaddr_in addr;
	memset(&addr, 0, sizeof(addr));
	addr.sin_family = AF_INET;
	addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
	addr.sin_port = htons(LBJ_PORT);
	if (bind(lfd, (struct sockaddr *)&addr, sizeof(addr)) < 0 ||
	    listen(lfd, 1) < 0) {
		close(lfd);
		signal_started(-1001);
		goto out_dev;
	}
	S.listen_fd = lfd;
	signal_started(0);
	S.stage = 4;

	while (!S.stop) {
		fd_set rfds;
		struct timeval tv;
		FD_ZERO(&rfds);
		FD_SET(lfd, &rfds);
		tv.tv_sec = 0;
		tv.tv_usec = 200000;
		if (select(lfd + 1, &rfds, NULL, NULL, &tv) <= 0)
			continue;

		int cfd = accept(lfd, NULL, NULL);
		if (cfd < 0)
			continue;
		S.client_fd = cfd;
		S.send_failed = 0;

		uint32_t header[3];
		memcpy(header, "RTL0", 4);
		header[1] = htonl((uint32_t)rtlsdr_get_tuner_type(dev));
		header[2] = htonl((uint32_t)rtlsdr_get_tuner_gains(dev, NULL));
		if (send(cfd, header, sizeof(header), MSG_NOSIGNAL) != (ssize_t)sizeof(header)) {
			close(cfd);
			S.client_fd = -1;
			continue;
		}

		pthread_t cmd_thread;
		pthread_create(&cmd_thread, NULL, command_main, NULL);
		S.stage = 5;
		r = rtlsdr_read_async(dev, stream_cb, NULL, 0, 0);
		S.stage = 4;
		if (S.client_fd >= 0)
			shutdown(S.client_fd, SHUT_RDWR);
		pthread_join(cmd_thread, NULL);
		close(cfd);
		S.client_fd = -1;
		if (r < 0) {
			S.exit_err = r;
			break;
		}
		if (S.send_failed)
			rtlsdr_reset_buffer(dev);
	}

	close(lfd);
	S.listen_fd = -1;
out_dev:
	rtlsdr_close(dev);
	S.dev = NULL;
	S.stage = 0;
	S.finished = 1;
	return NULL;
}

JNIEXPORT jint JNICALL
Java_org_noxylva_lbjconsole_flutter_LbjUsbNative_nativeStart(JNIEnv *env, jclass cls, jint fd)
{
	(void)env; (void)cls;
	pthread_mutex_lock(&S.lock);
	if (S.running && S.finished) {
		pthread_join(S.thread, NULL);
		S.running = 0;
		S.finished = 0;
	}
	if (S.running) {
		pthread_mutex_unlock(&S.lock);
		return -2000;
	}
	S.stop = 0;
	S.started = 0;
	S.start_err = 0;
	S.exit_err = 0;
	S.finished = 0;
	S.dev = NULL;
	S.listen_fd = -1;
	S.client_fd = -1;
	S.send_failed = 0;
	S.stage = 0;
	if (pthread_create(&S.thread, NULL, session_main, (void *)(intptr_t)fd) != 0) {
		pthread_mutex_unlock(&S.lock);
		return -2001;
	}
	S.running = 1;
	while (!S.started)
		pthread_cond_wait(&S.started_cond, &S.lock);
	int err = S.start_err;
	pthread_mutex_unlock(&S.lock);
	if (err != 0)
		Java_org_noxylva_lbjconsole_flutter_LbjUsbNative_nativeStop(env, cls);
	return err;
}

JNIEXPORT void JNICALL
Java_org_noxylva_lbjconsole_flutter_LbjUsbNative_nativeStop(JNIEnv *env, jclass cls)
{
	(void)env; (void)cls;
	lbj_pluto_stop();
	pthread_mutex_lock(&S.lock);
	if (!S.running) {
		pthread_mutex_unlock(&S.lock);
		return;
	}
	if (S.finished) {
		pthread_t done_thread = S.thread;
		S.running = 0;
		S.finished = 0;
		pthread_mutex_unlock(&S.lock);
		pthread_join(done_thread, NULL);
		return;
	}
	S.stop = 1;
	rtlsdr_dev_t *dev = S.dev;
	int cfd = S.client_fd;
	pthread_t thread = S.thread;
	S.running = 0;
	pthread_mutex_unlock(&S.lock);

	if (dev)
		rtlsdr_cancel_async(dev);
	if (cfd >= 0)
		shutdown(cfd, SHUT_RDWR);
	pthread_join(thread, NULL);
}

JNIEXPORT jboolean JNICALL
Java_org_noxylva_lbjconsole_flutter_LbjUsbNative_nativeIsRunning(JNIEnv *env, jclass cls)
{
	(void)env; (void)cls;
	return ((S.running && !S.finished) || lbj_pluto_running()) ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jint JNICALL
Java_org_noxylva_lbjconsole_flutter_LbjUsbNative_nativeExitError(JNIEnv *env, jclass cls)
{
	(void)env; (void)cls;
	if (S.finished && S.exit_err != 0)
		return S.exit_err;
	return lbj_pluto_exit_error();
}

JNIEXPORT jstring JNICALL
Java_org_noxylva_lbjconsole_flutter_LbjUsbNative_nativeStage(JNIEnv *env, jclass cls)
{
	(void)cls;
	char buf[64];
	snprintf(buf, sizeof(buf), "rtl%d/pluto%d", S.stage, lbj_pluto_stage());
	return (*env)->NewStringUTF(env, buf);
}

JNIEXPORT jint JNICALL
Java_org_noxylva_lbjconsole_flutter_LbjUsbNative_nativeReset(JNIEnv *env, jclass cls, jint fd)
{
	(void)env; (void)cls;
	return ioctl((int)fd, USBDEVFS_RESET, 0);
}

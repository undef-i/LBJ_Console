#include <jni.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>
#include <sys/socket.h>
#include <sys/select.h>
#include <netinet/in.h>
#include <arpa/inet.h>

#include "libusb.h"

#define PLUTO_PORT 14423
#define PLUTO_FREQ_HZ 821237500
#define PLUTO_RATE_HZ 2400000
#define PLUTO_BUF_SAMPLES 8192
#define PLUTO_READ_SAMPLES 4100
#define PLUTO_READ_BYTES (PLUTO_READ_SAMPLES * 4)
#define PLUTO_DECIM 10

struct pio {
	libusb_device_handle *h;
	unsigned char ep_in;
	unsigned char ep_out;
	unsigned char buf[32768];
	int len;
	int pos;
};

static struct {
	pthread_mutex_t lock;
	pthread_cond_t started_cond;
	pthread_mutex_t ctl_lock;
	pthread_t thread;
	libusb_context *ctx;
	libusb_device_handle *h;
	struct pio p0;
	struct pio p1;
	char phy_id[32];
	char rx_id[32];
	int ifnum;
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
} P = {
	PTHREAD_MUTEX_INITIALIZER, PTHREAD_COND_INITIALIZER,
	PTHREAD_MUTEX_INITIALIZER,
	0, NULL, NULL, {0}, {0}, "", "", 0, 0, 0, 0, 0, 0, -1, -1, 0, 0,
};

static int pio_fill(struct pio *p)
{
	int transferred = 0;
	int r = libusb_bulk_transfer(p->h, p->ep_in, p->buf,
		(int)sizeof(p->buf), &transferred, 1000);
	if (r == LIBUSB_ERROR_TIMEOUT) {
		if (transferred <= 0)
			return P.stop ? -1 : 0;
	} else if (r < 0) {
		return -1;
	}
	p->len = transferred;
	p->pos = 0;
	return transferred;
}

static int pio_read_exact(struct pio *p, unsigned char *out, int n)
{
	int got = 0;
	while (got < n) {
		if (P.stop)
			return -1;
		if (p->pos >= p->len) {
			int r = pio_fill(p);
			if (r < 0)
				return -1;
			if (r == 0)
				continue;
		}
		int avail = p->len - p->pos;
		int take = avail < n - got ? avail : n - got;
		memcpy(out + got, p->buf + p->pos, (size_t)take);
		p->pos += take;
		got += take;
	}
	return 0;
}

static int pio_read_line(struct pio *p, char *out, int cap)
{
	int n = 0;
	for (;;) {
		unsigned char c;
		if (pio_read_exact(p, &c, 1) < 0)
			return -1;
		if (c == '\n')
			break;
		if (c == '\r')
			continue;
		if (n < cap - 1)
			out[n++] = (char)c;
	}
	out[n] = 0;
	return n;
}

static int pio_write_all(struct pio *p, const void *data, int n)
{
	const unsigned char *b = data;
	int sent = 0;
	while (sent < n) {
		int transferred = 0;
		int r = libusb_bulk_transfer(p->h, p->ep_out,
			(unsigned char *)b + sent, n - sent, &transferred, 1000);
		if (r < 0 && r != LIBUSB_ERROR_TIMEOUT)
			return -1;
		sent += transferred;
		if (P.stop)
			return -1;
	}
	return 0;
}

static int iiod_value(struct pio *p, long *v)
{
	char line[64];
	if (pio_read_line(p, line, (int)sizeof(line)) < 0)
		return -1;
	*v = strtol(line, NULL, 10);
	return 0;
}

static int iiod_cmd(struct pio *p, const char *cmd)
{
	return pio_write_all(p, cmd, (int)strlen(cmd));
}

static int iiod_write_attr(struct pio *p, const char *dev, const char *dir,
	const char *chan, const char *attr, const char *value)
{
	char hdr[256];
	int vlen = (int)strlen(value);
	int n;
	if (dir)
		n = snprintf(hdr, sizeof(hdr), "WRITE %s %s %s %s %d\r\n",
			dev, dir, chan, attr, vlen);
	else
		n = snprintf(hdr, sizeof(hdr), "WRITE %s %s %d\r\n",
			dev, attr, vlen);
	if (n < 0 || pio_write_all(p, hdr, n) < 0)
		return -1;
	if (pio_write_all(p, value, vlen) < 0)
		return -1;
	long v;
	if (iiod_value(p, &v) < 0)
		return -1;
	return v < 0 ? -1 : 0;
}

static int iiod_set_timeout(struct pio *p, int ms)
{
	char cmd[64];
	snprintf(cmd, sizeof(cmd), "TIMEOUT %d\r\n", ms);
	if (iiod_cmd(p, cmd) < 0)
		return -1;
	long v;
	return iiod_value(p, &v);
}

static int xml_device_id(const char *xml, const char *name, char *out, int cap)
{
	char pat[128];
	snprintf(pat, sizeof(pat), "name=\"%s\"", name);
	const char *p = strstr(xml, pat);
	if (!p)
		return -1;
	const char *tag = p;
	while (tag > xml && *tag != '<')
		tag--;
	if (*tag != '<')
		return -1;
	const char *tagend = strchr(tag, '>');
	if (!tagend)
		return -1;
	const char *id = strstr(tag, "id=\"");
	if (!id || id > tagend)
		return -1;
	id += 4;
	const char *end = strchr(id, '"');
	if (!end || end > tagend)
		return -1;
	int n = (int)(end - id);
	if (n <= 0 || n >= cap)
		return -1;
	memcpy(out, id, (size_t)n);
	out[n] = 0;
	return 0;
}

static int pipe_ctrl(libusb_device_handle *h, int ifnum, int req, int pipe_id)
{
	return libusb_control_transfer(h,
		LIBUSB_REQUEST_TYPE_VENDOR | LIBUSB_RECIPIENT_INTERFACE,
		(unsigned char)req, (unsigned short)pipe_id,
		(unsigned short)ifnum, NULL, 0, 1000);
}

static int harvest_interface(libusb_device_handle *h, int ifnum,
		unsigned char *eps, int *npipes)
{
	libusb_device *dev = libusb_get_device(h);
	struct libusb_config_descriptor *cfg = NULL;
	if (libusb_get_active_config_descriptor(dev, &cfg) < 0)
		return -3011;
	int found = -1;
	for (int i = 0; i < cfg->bNumInterfaces && found < 0; i++) {
		for (int a = 0; a < cfg->interface[i].num_altsetting; a++) {
			const struct libusb_interface_descriptor *d =
				&cfg->interface[i].altsetting[a];
			if (d->bInterfaceNumber != ifnum)
				continue;
			if (d->bNumEndpoints < 4 || (d->bNumEndpoints % 2) != 0)
				continue;
			found = d->bInterfaceNumber;
			*npipes = d->bNumEndpoints / 2;
			if (*npipes > 4)
				*npipes = 4;
			for (int e = 0; e < *npipes * 2; e++)
				eps[e] = d->endpoint[e].bEndpointAddress;
		}
	}
	libusb_free_config_descriptor(cfg);
	if (found < 0)
		return -3013;
	return 0;
}

static int pluto_configure(void)
{
	char cmd[160];
	long v;

	P.stage = 3101;
	if (iiod_cmd(&P.p0, "PRINT\r\n") < 0)
		return -3101;
	P.stage = 3102;
	if (iiod_value(&P.p0, &v) < 0 || v <= 0 || v > 4 * 1024 * 1024)
		return -3102;
	int xml_len = (int)v;
	char *xml = malloc((size_t)xml_len + 2);
	if (!xml)
		return -3103;
	P.stage = 3104;
	if (pio_read_exact(&P.p0, (unsigned char *)xml, xml_len + 1) < 0) {
		free(xml);
		return -3104;
	}
	xml[xml_len] = 0;
	P.stage = 3105;
	int bad = xml_device_id(xml, "ad9361-phy", P.phy_id,
			(int)sizeof(P.phy_id)) < 0 ||
		xml_device_id(xml, "cf-ad9361-lpc", P.rx_id,
			(int)sizeof(P.rx_id)) < 0;
	free(xml);
	if (bad)
		return -3105;

	iiod_set_timeout(&P.p0, 2500);

	char val[32];
	snprintf(val, sizeof(val), "%d", PLUTO_FREQ_HZ);
	P.stage = 3106;
	if (iiod_write_attr(&P.p0, P.phy_id, "OUTPUT", "altvoltage0",
			"frequency", val) < 0)
		return -3106;
	snprintf(val, sizeof(val), "%d", PLUTO_RATE_HZ);
	P.stage = 3107;
	if (iiod_write_attr(&P.p0, P.phy_id, "INPUT", "voltage0",
			"sampling_frequency", val) < 0)
		return -3107;
	P.stage = 3108;
	if (iiod_write_attr(&P.p0, P.phy_id, "INPUT", "voltage0",
			"rf_bandwidth", "2000000") < 0)
		return -3108;
	P.stage = 3109;
	if (iiod_write_attr(&P.p0, P.phy_id, "INPUT", "voltage0",
			"gain_control_mode", "slow_attack") < 0)
		return -3109;

	P.stage = 3110;
	if (pipe_ctrl(P.h, P.ifnum, 1, 1) < 0)
		return -3110;
	snprintf(cmd, sizeof(cmd), "OPEN %s %d 00000003\r\n",
		P.rx_id, PLUTO_BUF_SAMPLES);
	P.stage = 3111;
	if (iiod_cmd(&P.p1, cmd) < 0 || iiod_value(&P.p1, &v) < 0 || v < 0)
		return -3111;
	iiod_set_timeout(&P.p1, 2500);
	return 0;
}

static int pluto_readbuf(unsigned char *out, int want)
{
	char cmd[128];
	snprintf(cmd, sizeof(cmd), "READBUF %s %d\r\n", P.rx_id, want);
	if (iiod_cmd(&P.p1, cmd) < 0)
		return -1;
	int got = 0;
	int first = 1;
	while (got < want) {
		long v;
		if (iiod_value(&P.p1, &v) < 0)
			return -1;
		if (v < 0)
			return -1;
		if (v == 0)
			break;
		if (first) {
			char mask[64];
			if (pio_read_line(&P.p1, mask, (int)sizeof(mask)) < 0)
				return -1;
			first = 0;
		}
		if (v > want - got)
			v = want - got;
		if (pio_read_exact(&P.p1, out + got, (int)v) < 0)
			return -1;
		got += (int)v;
	}
	return got;
}

struct pcmd {
	unsigned char cmd;
	unsigned int param;
} __attribute__((packed));

static void *pluto_command_main(void *arg)
{
	(void)arg;
	int fd = P.client_fd;
	while (!P.stop) {
		struct pcmd cmd;
		size_t got = 0;
		while (got < sizeof(cmd) && !P.stop) {
			fd_set rfds;
			struct timeval tv;
			FD_ZERO(&rfds);
			FD_SET(fd, &rfds);
			tv.tv_sec = 0;
			tv.tv_usec = 200000;
			if (select(fd + 1, &rfds, NULL, NULL, &tv) <= 0)
				continue;
			ssize_t n = recv(fd, (char *)&cmd + got,
				sizeof(cmd) - got, 0);
			if (n <= 0) {
				P.send_failed = 1;
				return NULL;
			}
			got += (size_t)n;
		}
		if (P.stop)
			return NULL;
		if (cmd.cmd == 0x01) {
			char val[32];
			snprintf(val, sizeof(val), "%u", ntohl(cmd.param));
			pthread_mutex_lock(&P.ctl_lock);
			iiod_write_attr(&P.p0, P.phy_id, "OUTPUT",
				"altvoltage0", "frequency", val);
			pthread_mutex_unlock(&P.ctl_lock);
		}
	}
	return NULL;
}

static void pluto_signal_started(int err)
{
	pthread_mutex_lock(&P.lock);
	P.start_err = err;
	P.started = 1;
	pthread_cond_signal(&P.started_cond);
	pthread_mutex_unlock(&P.lock);
}

static void *pluto_session_main(void *arg)
{
	int fd = (int)(intptr_t)arg;
	int r;

	P.stage = 1;
	struct libusb_init_option init_option;
	init_option.option = LIBUSB_OPTION_NO_DEVICE_DISCOVERY;
	init_option.value.ival = 0;
	r = libusb_init_context(&P.ctx, &init_option, 1);
	if (r < 0) {
		pluto_signal_started(-3001);
		P.stage = 0;
		P.finished = 1;
		return NULL;
	}
	r = libusb_wrap_sys_device(P.ctx, (intptr_t)fd, &P.h);
	if (r < 0 || !P.h) {
		pluto_signal_started(-3002);
		goto out_ctx;
	}

	unsigned char eps[8];
	int npipes = 0;
	P.stage = 2;
	int fr = harvest_interface(P.h, P.ifnum, eps, &npipes);
	if (fr < 0) {
		pluto_signal_started(fr);
		goto out_handle;
	}
	if (npipes < 2) {
		pluto_signal_started(-3014);
		goto out_handle;
	}
	P.p0.h = P.h;
	P.p0.ep_in = eps[0];
	P.p0.ep_out = eps[1];
	P.p1.h = P.h;
	P.p1.ep_in = eps[2];
	P.p1.ep_out = eps[3];

	P.stage = 3;
	if (libusb_claim_interface(P.h, P.ifnum) < 0) {
		pluto_signal_started(-3004);
		goto out_handle;
	}
	for (int e = 0; e < npipes * 2; e++)
		libusb_clear_halt(P.h, eps[e]);
	pipe_ctrl(P.h, P.ifnum, 0, 0);
	if (pipe_ctrl(P.h, P.ifnum, 1, 0) < 0) {
		pluto_signal_started(-3005);
		goto out_iface;
	}

	r = pluto_configure();
	if (r < 0) {
		pluto_signal_started(r);
		goto out_pipes;
	}

	int lfd = socket(AF_INET, SOCK_STREAM, 0);
	if (lfd < 0) {
		pluto_signal_started(-3006);
		goto out_pipes;
	}
	int on = 1;
	setsockopt(lfd, SOL_SOCKET, SO_REUSEADDR, &on, sizeof(on));
	struct sockaddr_in addr;
	memset(&addr, 0, sizeof(addr));
	addr.sin_family = AF_INET;
	addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
	addr.sin_port = htons(PLUTO_PORT);
	if (bind(lfd, (struct sockaddr *)&addr, sizeof(addr)) < 0 ||
	    listen(lfd, 1) < 0) {
		close(lfd);
		pluto_signal_started(-3007);
		goto out_pipes;
	}
	P.listen_fd = lfd;
	pluto_signal_started(0);
	P.stage = 4;

	static unsigned char raw[PLUTO_READ_BYTES];
	static unsigned char conv[PLUTO_READ_SAMPLES / PLUTO_DECIM * 2];
	while (!P.stop) {
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
		P.client_fd = cfd;
		P.send_failed = 0;

		uint32_t header[3];
		memcpy(header, "RTL0", 4);
		header[1] = htonl(5);
		header[2] = htonl(1);
		if (send(cfd, header, sizeof(header), MSG_NOSIGNAL) !=
		    (ssize_t)sizeof(header)) {
			close(cfd);
			P.client_fd = -1;
			continue;
		}

		pthread_t cmd_thread;
		pthread_create(&cmd_thread, NULL, pluto_command_main, NULL);
		P.stage = 5;
		while (!P.stop && !P.send_failed) {
			int got = pluto_readbuf(raw, PLUTO_READ_BYTES);
			if (got <= 0) {
				P.exit_err = got < 0 ? got : -3201;
				break;
			}
			P.exit_err = 0;
			int frames = got / 4;
			int groups = frames / PLUTO_DECIM;
			const int16_t *s = (const int16_t *)raw;
			for (int g = 0; g < groups; g++) {
				int si = 0, sq = 0;
				for (int k = 0; k < PLUTO_DECIM; k++) {
					si += s[(g * PLUTO_DECIM + k) * 2];
					sq += s[(g * PLUTO_DECIM + k) * 2 + 1];
				}
				conv[g * 2] = (unsigned char)((si / PLUTO_DECIM) / 16 + 128);
				conv[g * 2 + 1] = (unsigned char)((sq / PLUTO_DECIM) / 16 + 128);
			}
			int out_len = groups * 2;
			int off = 0;
			while (off < out_len && !P.stop) {
				ssize_t n = send(cfd, conv + off,
					(size_t)(out_len - off), MSG_NOSIGNAL);
				if (n <= 0) {
					P.send_failed = 1;
					break;
				}
				off += (int)n;
			}
		}
		if (P.client_fd >= 0)
			shutdown(P.client_fd, SHUT_RDWR);
		pthread_join(cmd_thread, NULL);
		close(cfd);
		P.client_fd = -1;
		P.stage = 4;
	}

	close(lfd);
	P.listen_fd = -1;
	P.stage = 7;
out_pipes:
	{
		char cmd[128];
		snprintf(cmd, sizeof(cmd), "CLOSE %s\r\n", P.rx_id);
		iiod_cmd(&P.p1, cmd);
		long v;
		iiod_value(&P.p1, &v);
	}
	pipe_ctrl(P.h, P.ifnum, 2, 1);
	pipe_ctrl(P.h, P.ifnum, 0, 0);
out_iface:
	libusb_release_interface(P.h, P.ifnum);
out_handle:
	libusb_close(P.h);
	P.h = NULL;
out_ctx:
	libusb_exit(P.ctx);
	P.ctx = NULL;
	P.stage = 0;
	P.finished = 1;
	return NULL;
}

int lbj_pluto_running(void)
{
	return P.running && !P.finished;
}

int lbj_pluto_stage(void)
{
	return P.stage;
}

int lbj_pluto_exit_error(void)
{
	return P.exit_err;
}

void lbj_pluto_stop(void)
{
	pthread_mutex_lock(&P.lock);
	if (!P.running) {
		pthread_mutex_unlock(&P.lock);
		return;
	}
	if (P.finished) {
		pthread_t done_thread = P.thread;
		P.running = 0;
		P.finished = 0;
		pthread_mutex_unlock(&P.lock);
		pthread_join(done_thread, NULL);
		return;
	}
	P.stop = 1;
	int cfd = P.client_fd;
	pthread_t thread = P.thread;
	P.running = 0;
	pthread_mutex_unlock(&P.lock);

	if (cfd >= 0)
		shutdown(cfd, SHUT_RDWR);
	pthread_join(thread, NULL);
}

JNIEXPORT jint JNICALL
Java_org_noxylva_lbjconsole_flutter_LbjUsbNative_nativeStartPluto(JNIEnv *env, jclass cls, jint fd, jint ifnum)
{
	(void)env; (void)cls;
	pthread_mutex_lock(&P.lock);
	if (P.running && P.finished) {
		pthread_join(P.thread, NULL);
		P.running = 0;
		P.finished = 0;
	}
	if (P.running) {
		pthread_mutex_unlock(&P.lock);
		return -2000;
	}
	P.stop = 0;
	P.started = 0;
	P.start_err = 0;
	P.exit_err = 0;
	P.finished = 0;
	P.h = NULL;
	P.ctx = NULL;
	P.p0.len = P.p0.pos = 0;
	P.p1.len = P.p1.pos = 0;
	P.phy_id[0] = 0;
	P.rx_id[0] = 0;
	P.listen_fd = -1;
	P.client_fd = -1;
	P.send_failed = 0;
	P.stage = 0;
	P.ifnum = (int)ifnum;
	if (pthread_create(&P.thread, NULL, pluto_session_main,
			(void *)(intptr_t)fd) != 0) {
		pthread_mutex_unlock(&P.lock);
		return -2001;
	}
	P.running = 1;
	while (!P.started)
		pthread_cond_wait(&P.started_cond, &P.lock);
	int err = P.start_err;
	pthread_mutex_unlock(&P.lock);
	if (err != 0)
		lbj_pluto_stop();
	return err;
}

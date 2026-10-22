#include <jni.h>
#include <string>
#include <thread>
#include <atomic>
#include <mutex>
#include <vector>
#include <sstream>
#include <iomanip>
#include <chrono>
#include <cmath>
#include <unistd.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <fcntl.h>
#include <android/log.h>
#include <errno.h>
#include "demod.h"
#include "audio_demod.h"
#include "audio_fft.h"

#define BUF_SIZE 8192
#define RTL_TCP_HEADER_SIZE 12
#define RTL_TCP_SAMPLE_RATE 240000

static std::thread workerThread;
static std::atomic<bool> running(false);
static std::atomic<int> sockfd_atomic(-1);

static std::mutex msgMutex;
static std::vector<std::string> micMessageBuffer;
static std::vector<std::string> rtlMessageBuffer;

static std::mutex micMutex;
static std::mutex rtlMutex;
static std::mutex fftMutex;
static AudioFFT* audioFFT = nullptr;

static JavaVM *g_vm = nullptr;
static jobject g_obj = nullptr;

void clientThread(std::string host, int port);

static void collectMessage(DemodState &state, std::vector<std::string> &buffer)
{
    std::ostringstream ss;
    std::lock_guard<std::mutex> msgLock(msgMutex);

    std::string message_content;
    if (state.function_bits == 3) {
        message_content = state.alpha_msg;
    } else {
        message_content = state.numeric_msg;
    }
    if (message_content.empty()) {
        message_content = state.alpha_msg.empty() ? state.numeric_msg : state.alpha_msg;
    }

    __android_log_print(ANDROID_LOG_DEBUG, "DEMOD",
        "msg_ready: addr=%u func=%d alpha_len=%zu numeric_len=%zu",
        state.address, state.function_bits, state.alpha_msg.length(), state.numeric_msg.length());

    ss << "[MSG]" << state.address << "|" << state.function_bits << "|" << message_content;
    buffer.push_back(ss.str());

    state.is_message_ready = false;
    state.numeric_msg.clear();
    state.alpha_msg.clear();
}

static jbyteArray drainMessages(JNIEnv *env, std::vector<std::string> &buffer)
{
    std::lock_guard<std::mutex> msgLock(msgMutex);

    if (buffer.empty())
    {
        return env->NewByteArray(0);
    }
    std::ostringstream ss;
    for (auto &msg : buffer)
        ss << msg << "\n";
    buffer.clear();

    std::string result = ss.str();
    jbyteArray byteArray = env->NewByteArray(result.size());
    env->SetByteArrayRegion(byteArray, 0, result.size(), (const jbyte*)result.c_str());
    return byteArray;
}

extern "C" JNIEXPORT void JNICALL
Java_org_noxylva_lbjconsole_flutter_RtlTcpChannelHandler_nativeStopClient(JNIEnv *, jobject)
{
    __android_log_print(ANDROID_LOG_DEBUG, "RTL-TCP", "stop_client");
    running = false;
    int old_sockfd = sockfd_atomic.exchange(-1);
    if (old_sockfd >= 0)
    {
        __android_log_print(ANDROID_LOG_DEBUG, "RTL-TCP", "close_sock: %d", old_sockfd);
        close(old_sockfd);
    }
    else
    {
        __android_log_print(ANDROID_LOG_DEBUG, "RTL-TCP", "sock_closed");
    }
    if (workerThread.joinable())
    {
        workerThread.detach();
    }
    {
        std::lock_guard<std::mutex> lock(msgMutex);
        rtlMessageBuffer.clear();
    }
    __android_log_print(ANDROID_LOG_DEBUG, "RTL-TCP", "stop_done");
}

extern "C" JNIEXPORT void JNICALL
Java_org_noxylva_lbjconsole_flutter_RtlTcpChannelHandler_startClientAsync(
    JNIEnv *env, jobject thiz, jstring host_, jstring port_)
{
    const char *host = env->GetStringUTFChars(host_, nullptr);
    const char *portStr = env->GetStringUTFChars(port_, nullptr);
    int port = atoi(portStr);
    if (g_obj == nullptr)
    {
        env->GetJavaVM(&g_vm);
        g_obj = env->NewGlobalRef(thiz);
    }
    if (workerThread.joinable())
    {
        workerThread.detach();
    }
    if (running)
    {
        env->ReleaseStringUTFChars(host_, host);
        env->ReleaseStringUTFChars(port_, portStr);
        return;
    }
    running = true;
    workerThread = std::thread(clientThread, std::string(host), port);
    workerThread.detach();
    env->ReleaseStringUTFChars(host_, host);
    env->ReleaseStringUTFChars(port_, portStr);
}

extern "C" JNIEXPORT void JNICALL
Java_org_noxylva_lbjconsole_flutter_AudioInputHandler_nativePushAudio(
        JNIEnv *env, jobject thiz, jshortArray audioData, jint size) {

    jshort *samples = env->GetShortArrayElements(audioData, NULL);

    {
        std::lock_guard<std::mutex> fftLock(fftMutex);
        if (!audioFFT) {
            audioFFT = new AudioFFT(4096);
        }
        audioFFT->processSamples(samples, size);
    }

    {
        std::lock_guard<std::mutex> micLock(micMutex);
        processAudioSamples(samples, size);

        if (demodMic.is_message_ready) {
            collectMessage(demodMic, micMessageBuffer);
        }
    }

    env->ReleaseShortArrayElements(audioData, samples, 0);
}

extern "C" JNIEXPORT jdouble JNICALL
Java_org_noxylva_lbjconsole_flutter_RtlTcpChannelHandler_getSignalStrength(JNIEnv *, jobject)
{
    return (jdouble)demodRtl.magsqRaw;
}

extern "C" JNIEXPORT void JNICALL
Java_org_noxylva_lbjconsole_flutter_AudioInputHandler_clearMessageBuffer(JNIEnv *, jobject)
{
    std::lock_guard<std::mutex> micLock(micMutex);
    {
        std::lock_guard<std::mutex> msgLock(msgMutex);
        micMessageBuffer.clear();
    }
    resetAudioDemod();
    resetDemod(demodMic);
}

extern "C" JNIEXPORT jfloatArray JNICALL
Java_org_noxylva_lbjconsole_flutter_AudioInputHandler_getAudioSpectrum(JNIEnv *env, jobject)
{
    std::lock_guard<std::mutex> fftLock(fftMutex);

    if (!audioFFT) {
        return env->NewFloatArray(0);
    }

    int spectrumSize = audioFFT->getFFTSize() / 2;
    std::vector<float> spectrum(spectrumSize);
    audioFFT->getSpectrum(spectrum.data(), spectrumSize);

    const int outputBins = 500;
    std::vector<float> downsampled(outputBins);

    for (int i = 0; i < outputBins; i++) {
        int begin = (i * spectrumSize) / outputBins;
        int end = ((i + 1) * spectrumSize) / outputBins;
        float peak = 0.0f;
        for (int j = begin; j < end; j++) {
            if (spectrum[j] > peak) peak = spectrum[j];
        }
        downsampled[i] = peak;
    }

    jfloatArray result = env->NewFloatArray(outputBins);
    env->SetFloatArrayRegion(result, 0, outputBins, downsampled.data());
    return result;
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_org_noxylva_lbjconsole_flutter_AudioInputHandler_pollMessages(JNIEnv *env, jobject)
{
    return drainMessages(env, micMessageBuffer);
}

extern "C" JNIEXPORT jboolean JNICALL
Java_org_noxylva_lbjconsole_flutter_RtlTcpChannelHandler_isConnected(JNIEnv *, jobject)
{
    return (running && sockfd_atomic.load() >= 0) ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_org_noxylva_lbjconsole_flutter_RtlTcpChannelHandler_pollMessages(JNIEnv *env, jobject /*this*/)
{
    return drainMessages(env, rtlMessageBuffer);
}

static bool readExact(int fd, uint8_t *out, int count)
{
    int got = 0;
    while (got < count)
    {
        fd_set readfds;
        FD_ZERO(&readfds);
        FD_SET(fd, &readfds);
        struct timeval timeout;
        timeout.tv_sec = 5;
        timeout.tv_usec = 0;
        int ready = select(fd + 1, &readfds, NULL, NULL, &timeout);
        if (ready <= 0)
        {
            return false;
        }
        ssize_t n = read(fd, out + got, count - got);
        if (n <= 0)
        {
            return false;
        }
        got += (int)n;
    }
    return true;
}

static bool sendRtlCommand(int fd, uint8_t command, uint32_t parameter)
{
    uint8_t buf[5];
    buf[0] = command;
    buf[1] = (uint8_t)(parameter >> 24);
    buf[2] = (uint8_t)(parameter >> 16);
    buf[3] = (uint8_t)(parameter >> 8);
    buf[4] = (uint8_t)(parameter);
    int sent = 0;
    while (sent < 5)
    {
        ssize_t n = send(fd, buf + sent, 5 - sent, 0);
        if (n <= 0)
        {
            return false;
        }
        sent += (int)n;
    }
    return true;
}

static int8_t clampToInt8(double value)
{
    long v = lround(value);
    if (v > 127) v = 127;
    if (v < -128) v = -128;
    return (int8_t)v;
}

void clientThread(std::string host, int port)
{
    int localSockfd = -1;
    struct sockaddr_in servaddr;
    uint8_t buffer[BUF_SIZE];
    ssize_t n;
    int flags = 0;
    int connectResult = 0;
    bool connected = false;
    fd_set writefds;
    struct timeval timeout;
    int selectResult = 0;
    int so_error = 0;
    socklen_t len = 0;
    int decim_counter = 0;

    {
        std::lock_guard<std::mutex> rtlLock(rtlMutex);
        resetDemod(demodRtl);
    }

    localSockfd = socket(AF_INET, SOCK_STREAM, 0);
    if (localSockfd < 0)
    {
        goto cleanup;
    }
    memset(&servaddr, 0, sizeof(servaddr));
    servaddr.sin_family = AF_INET;
    servaddr.sin_port = htons(port);
    servaddr.sin_addr.s_addr = inet_addr(host.c_str());
    flags = fcntl(localSockfd, F_GETFL, 0);
    fcntl(localSockfd, F_SETFL, flags | O_NONBLOCK);
    connectResult = connect(localSockfd, (struct sockaddr *)&servaddr, sizeof(servaddr));
    if (connectResult == 0)
    {
        connected = true;
    }
    else if (errno == EINPROGRESS)
    {
        FD_ZERO(&writefds);
        FD_SET(localSockfd, &writefds);
        timeout.tv_sec = 5;
        timeout.tv_usec = 0;
        selectResult = select(localSockfd + 1, NULL, &writefds, NULL, &timeout);
        if (selectResult > 0)
        {
            len = sizeof(so_error);
            getsockopt(localSockfd, SOL_SOCKET, SO_ERROR, &so_error, &len);
            if (so_error == 0)
            {
                connected = true;
            }
        }
    }
    fcntl(localSockfd, F_SETFL, flags);
    if (!connected)
    {
        __android_log_print(ANDROID_LOG_ERROR, "RTL-TCP", "conn_fail");
        goto cleanup;
    }

    sockfd_atomic.store(localSockfd);

    {
        uint8_t header[RTL_TCP_HEADER_SIZE];
        if (!readExact(localSockfd, header, RTL_TCP_HEADER_SIZE) ||
            header[0] != 'R' || header[1] != 'T' || header[2] != 'L' || header[3] != '0')
        {
            __android_log_print(ANDROID_LOG_ERROR, "RTL-TCP", "bad_header");
            goto cleanup;
        }
        uint32_t tunerType = ((uint32_t)header[4] << 24) | ((uint32_t)header[5] << 16) |
                             ((uint32_t)header[6] << 8) | (uint32_t)header[7];
        uint32_t gainCount = ((uint32_t)header[8] << 24) | ((uint32_t)header[9] << 16) |
                             ((uint32_t)header[10] << 8) | (uint32_t)header[11];
        __android_log_print(ANDROID_LOG_DEBUG, "RTL-TCP", "header: tuner=%u gains=%u", tunerType, gainCount);
    }

    if (!sendRtlCommand(localSockfd, 0x02, RTL_TCP_SAMPLE_RATE) ||
        !sendRtlCommand(localSockfd, 0x03, 1) ||
        !sendRtlCommand(localSockfd, 0x08, 1))
    {
        __android_log_print(ANDROID_LOG_ERROR, "RTL-TCP", "cmd_fail");
        goto cleanup;
    }
    __android_log_print(ANDROID_LOG_DEBUG, "RTL-TCP", "cmd_ok: rate=%d gain=auto agc=on", RTL_TCP_SAMPLE_RATE);

    {
        std::lock_guard<std::mutex> lock(msgMutex);
        rtlMessageBuffer.emplace_back("Connected to " + host + ":" + std::to_string(port) + "\n");
    }

    {
        bool haveCarry = false;
        uint8_t carryByte = 0;

        while (running && (n = read(localSockfd, buffer, BUF_SIZE)) > 0)
        {
            for (int j = 0; j < n; j++)
            {
                if (!haveCarry)
                {
                    carryByte = buffer[j];
                    haveCarry = true;
                    continue;
                }
                haveCarry = false;

                double filt_i = demodRtl.decimationLowpassI.filter((double)carryByte - 128.0);
                double filt_q = demodRtl.decimationLowpassQ.filter((double)buffer[j] - 128.0);

                if (++decim_counter == DECIMATION)
                {
                    decim_counter = 0;

                    std::lock_guard<std::mutex> rtlLock(rtlMutex);
                    processOneSample(demodRtl, clampToInt8(filt_i), clampToInt8(filt_q));

                    if (demodRtl.is_message_ready)
                    {
                        collectMessage(demodRtl, rtlMessageBuffer);
                    }
                }
            }
        }
    }

    if (n < 0 && running)
    {
        __android_log_print(ANDROID_LOG_ERROR, "RTL-TCP", "read_err: %s", strerror(errno));
    }
    else if (n == 0)
    {
        __android_log_print(ANDROID_LOG_DEBUG, "RTL-TCP", "srv_closed");
    }

cleanup:
    int old_sockfd = sockfd_atomic.exchange(-1);
    if (old_sockfd >= 0)
    {
        close(old_sockfd);
    }

    running = false;
    __android_log_print(ANDROID_LOG_DEBUG, "RTL-TCP", "thread_exit");
}

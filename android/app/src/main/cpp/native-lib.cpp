#include <jni.h>
#include <string>
#include <thread>
#include <atomic>
#include <mutex>
#include <vector>
#include <sstream>
#include <iomanip>
#include <chrono>
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

static std::thread workerThread;
static std::atomic<bool> running(false);
static std::atomic<int> sockfd_atomic(-1);

static std::mutex msgMutex;
static std::vector<std::string> messageBuffer;

static std::mutex demodDataMutex;
static std::mutex fftMutex;
static AudioFFT* audioFFT = nullptr;

static JavaVM *g_vm = nullptr;
static jobject g_obj = nullptr;

void clientThread(std::string host, int port);

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
        messageBuffer.clear();
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
    
    ensureDSPInitialized();

    jshort *samples = env->GetShortArrayElements(audioData, NULL);
    
    {
        std::lock_guard<std::mutex> fftLock(fftMutex);
        if (!audioFFT) {
            audioFFT = new AudioFFT(4096);
        }
        audioFFT->processSamples(samples, size);
    }
    
    std::lock_guard<std::mutex> demodLock(demodDataMutex);

    processAudioSamples(samples, size);
    
    if (is_message_ready) {
        std::ostringstream ss;
        std::lock_guard<std::mutex> msgLock(msgMutex);

        std::string message_content;
        if (function_bits == 3) {
            message_content = alpha_msg;
        } else {
            message_content = numeric_msg;
        }
        if (message_content.empty()) {
            message_content = alpha_msg.empty() ? numeric_msg : alpha_msg;
        }

        __android_log_print(ANDROID_LOG_DEBUG, "AUDIO", 
            "msg_ready: addr=%u func=%d alpha_len=%zu numeric_len=%zu",
            address, function_bits, alpha_msg.length(), numeric_msg.length());

        ss << "[MSG]" << address << "|" << function_bits << "|" << message_content;
        messageBuffer.push_back(ss.str());

        is_message_ready = false;
        numeric_msg.clear();
        alpha_msg.clear();
    }

    env->ReleaseShortArrayElements(audioData, samples, 0);
}

extern "C" JNIEXPORT jdouble JNICALL
Java_org_noxylva_lbjconsole_flutter_RtlTcpChannelHandler_getSignalStrength(JNIEnv *, jobject)
{
    return (jdouble)magsqRaw;
}

extern "C" JNIEXPORT void JNICALL
Java_org_noxylva_lbjconsole_flutter_AudioInputHandler_clearMessageBuffer(JNIEnv *, jobject)
{
    std::lock_guard<std::mutex> demodLock(demodDataMutex);
    std::lock_guard<std::mutex> msgLock(msgMutex);
    messageBuffer.clear();
    is_message_ready = false;
    numeric_msg.clear();
    alpha_msg.clear();
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
        int srcIdx = (i * spectrumSize) / outputBins;
        downsampled[i] = spectrum[srcIdx];
    }
    
    jfloatArray result = env->NewFloatArray(outputBins);
    env->SetFloatArrayRegion(result, 0, outputBins, downsampled.data());
    return result;
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_org_noxylva_lbjconsole_flutter_AudioInputHandler_pollMessages(JNIEnv *env, jobject)
{
    std::lock_guard<std::mutex> demodLock(demodDataMutex);
    std::lock_guard<std::mutex> msgLock(msgMutex);

    if (messageBuffer.empty())
    {
        return env->NewByteArray(0);
    }
    std::ostringstream ss;
    for (auto &msg : messageBuffer)
        ss << msg << "\n";
    messageBuffer.clear();
    
    std::string result = ss.str();
    jbyteArray byteArray = env->NewByteArray(result.size());
    env->SetByteArrayRegion(byteArray, 0, result.size(), (const jbyte*)result.c_str());
    return byteArray;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_org_noxylva_lbjconsole_flutter_RtlTcpChannelHandler_isConnected(JNIEnv *, jobject)
{
    return (running && sockfd_atomic.load() >= 0) ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_org_noxylva_lbjconsole_flutter_RtlTcpChannelHandler_pollMessages(JNIEnv *env, jobject /*this*/)
{
    std::lock_guard<std::mutex> demodLock(demodDataMutex);

    std::lock_guard<std::mutex> msgLock(msgMutex);

    if (messageBuffer.empty())
    {
        return env->NewByteArray(0);
    }
    std::ostringstream ss;
    for (auto &msg : messageBuffer)
        ss << msg << "\n";
    messageBuffer.clear();
    
    std::string result = ss.str();
    jbyteArray byteArray = env->NewByteArray(result.size());
    env->SetByteArrayRegion(byteArray, 0, result.size(), (const jbyte*)result.c_str());
    return byteArray;
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
    const int DECIM = 5;
    int decim_counter = 0;
    uint32_t acc_i = 0, acc_q = 0;

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

    ensureDSPInitialized();
    
    sockfd_atomic.store(localSockfd);
    {
        std::lock_guard<std::mutex> lock(msgMutex);
        messageBuffer.emplace_back("Connected to " + host + ":" + std::to_string(port) + "\n");
    }

    while (running && (n = read(localSockfd, buffer, BUF_SIZE)) > 0)
    {
        for (int j = 0; j < n; j += 2)
        {
            acc_i += buffer[j];
            acc_q += buffer[j + 1];
            if (++decim_counter == DECIM)
            {
                int8_t i_ds = (int8_t)(((float)acc_i / DECIM) - 128);
                int8_t q_ds = (int8_t)(((float)acc_q / DECIM) - 128);

                std::lock_guard<std::mutex> demodLock(demodDataMutex);
                processOneSample(i_ds, q_ds);

                if (is_message_ready)
                {
                    std::ostringstream ss;
                    std::lock_guard<std::mutex> msgLock(msgMutex);

                    std::ostringstream alpha_hex;
                    for (unsigned char ch : alpha_msg) {
                        alpha_hex << std::hex << std::uppercase << (int)ch << ",";
                    }
                    __android_log_print(ANDROID_LOG_DEBUG, "RTL-TCP", "alpha_msg_bytes: %s", alpha_hex.str().c_str());
                    __android_log_print(ANDROID_LOG_DEBUG, "RTL-TCP", "numeric_msg: %s func=%d", numeric_msg.c_str(), function_bits);

                    std::string message_content;
                    if (function_bits == 3) {
                        message_content = alpha_msg;
                    } else {
                        message_content = numeric_msg;
                    }
                    if (message_content.empty()) {
                        message_content = alpha_msg.empty() ? numeric_msg : alpha_msg;
                    }

                    ss << "[MSG]" << address << "|" << function_bits << "|" << message_content;
                    messageBuffer.push_back(ss.str());

                    is_message_ready = false;
                    numeric_msg.clear();
                    alpha_msg.clear();
                }

                acc_i = acc_q = 0;
                decim_counter = 0;
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
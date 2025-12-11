#include "audio_fft.h"
#include <cmath>
#include <algorithm>
#include <android/log.h>

#define LOG_TAG "AudioFFT"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

AudioFFT::AudioFFT(int fftSize) 
    : fftSize_(fftSize)
    , inputBuffer_(fftSize, 0.0f)
    , windowBuffer_(fftSize, 0.0f)
    , realPart_(fftSize, 0.0f)
    , imagPart_(fftSize, 0.0f)
    , magnitude_(fftSize, 0.0f)
    , bufferPos_(0) {
    
    for (int i = 0; i < fftSize_; i++) {
        windowBuffer_[i] = 0.54f - 0.46f * std::cos(2.0f * M_PI * i / (fftSize_ - 1));
    }
    
    LOGD("AudioFFT initialized with size %d", fftSize_);
}

AudioFFT::~AudioFFT() {
}

void AudioFFT::processSamples(const int16_t* samples, int size) {
    for (int i = 0; i < size; i++) {
        inputBuffer_[bufferPos_] = samples[i] / 32768.0f;
        bufferPos_++;
        
        if (bufferPos_ >= fftSize_) {
            computeFFT();
            bufferPos_ = 0;
        }
    }
}

void AudioFFT::applyWindow() {
    for (int i = 0; i < fftSize_; i++) {
        realPart_[i] = inputBuffer_[i] * windowBuffer_[i];
        imagPart_[i] = 0.0f;
    }
}

void AudioFFT::computeFFT() {
    applyWindow();
    
    int n = fftSize_;
    
    int j = 0;
    for (int i = 0; i < n - 1; i++) {
        if (i < j) {
            std::swap(realPart_[i], realPart_[j]);
            std::swap(imagPart_[i], imagPart_[j]);
        }
        int k = n / 2;
        while (k <= j) {
            j -= k;
            k /= 2;
        }
        j += k;
    }
    
    for (int len = 2; len <= n; len *= 2) {
        float angle = -2.0f * M_PI / len;
        float wlenReal = std::cos(angle);
        float wlenImag = std::sin(angle);
        
        for (int i = 0; i < n; i += len) {
            float wReal = 1.0f;
            float wImag = 0.0f;
            
            for (int k = 0; k < len / 2; k++) {
                int idx1 = i + k;
                int idx2 = i + k + len / 2;
                
                float tReal = wReal * realPart_[idx2] - wImag * imagPart_[idx2];
                float tImag = wReal * imagPart_[idx2] + wImag * realPart_[idx2];
                
                realPart_[idx2] = realPart_[idx1] - tReal;
                imagPart_[idx2] = imagPart_[idx1] - tImag;
                realPart_[idx1] += tReal;
                imagPart_[idx1] += tImag;
                
                float wTempReal = wReal * wlenReal - wImag * wlenImag;
                wImag = wReal * wlenImag + wImag * wlenReal;
                wReal = wTempReal;
            }
        }
    }
    
    for (int i = 0; i < fftSize_; i++) {
        float real = realPart_[i];
        float imag = imagPart_[i];
        magnitude_[i] = std::sqrt(real * real + imag * imag);
    }
}

void AudioFFT::getSpectrum(float* output, int outputSize) {
    int copySize = std::min(outputSize, fftSize_ / 2);
    
    for (int i = 0; i < copySize; i++) {
        float mag = magnitude_[i];
        if (mag < 1e-10f) mag = 1e-10f;
        
        float db = 20.0f * std::log10(mag);
        
        float normalized = (db + 80.0f) / 80.0f;
        output[i] = std::max(0.0f, std::min(1.0f, normalized));
    }
}

#ifndef AUDIO_FFT_H
#define AUDIO_FFT_H

#include <cstdint>
#include <vector>

class AudioFFT {
public:
    AudioFFT(int fftSize = 256);
    ~AudioFFT();
    
    void processSamples(const int16_t* samples, int size);
    void getSpectrum(float* output, int outputSize);
    int getFFTSize() const { return fftSize_; }
    
private:
    void computeFFT();
    void applyWindow();
    
    int fftSize_;
    std::vector<float> inputBuffer_;
    std::vector<float> windowBuffer_;
    std::vector<float> realPart_;
    std::vector<float> imagPart_;
    std::vector<float> magnitude_;
    int bufferPos_;
};

#endif

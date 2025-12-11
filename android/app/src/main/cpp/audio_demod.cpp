#include "audio_demod.h"
#include "demod.h"
#include <android/log.h>
#include <cmath>
#include <cstring>

#define LOG_TAG "AudioDemod"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)

#define FINE_CLKT_HI 1.90
#define FINE_CLKT_LO 0.32
#define SAMPLE_RATE 48000
#define BAUD_RATE 1200

static double watch_ctr = 0.0;
static double atb_ctr = 0.0;
static double clkt = (double)SAMPLE_RATE / BAUD_RATE;
static int last_value = 0;
static int preamble_count = 0;
static int pocbit = 0;
static bool preamble_detected = false;
static int crossing_count = 0;
static int nSamples = 0;

static const int AUDIO_THRESHOLD = 128;

void resetAudioDemod() {
    watch_ctr = 0.0;
    atb_ctr = 0.0;
    clkt = (double)SAMPLE_RATE / BAUD_RATE;
    last_value = 0;
    preamble_count = 0;
    pocbit = 0;
    preamble_detected = false;
    crossing_count = 0;
    nSamples = 0;
    LOGD("Audio demodulator reset");
}

void processAudioSamples(int16_t *samples, int size) {
    for (int i = 0; i < size; i++) {
        int audio_value = (samples[i] + 32768) / 256;
        
        if (audio_value < 0) audio_value = 0;
        if (audio_value > 255) audio_value = 255;
        
        int current_bit = (audio_value > AUDIO_THRESHOLD) ? 1 : 0;
        
        if (current_bit != last_value) {
            crossing_count++;
            
            if ((nSamples > 28) && (nSamples < 44)) {
                preamble_count++;
                
                if (preamble_count > 50 && !preamble_detected) {
                    preamble_detected = true;
                    pocbit = 0;
                    LOGD("Preamble detected! crossings=%d samples=%d", preamble_count, nSamples);
                }
            }
            
            nSamples = 0;
        }
        
        nSamples++;
        last_value = current_bit;
        
        watch_ctr += 1.0;
        
        if (watch_ctr - atb_ctr < 1.0) {
            int bit = current_bit;
            
            if (preamble_detected) {
                processBasebandSample(bit);
                pocbit++;
                
                if (pocbit > 1250) {
                    LOGD("POCSAG timeout - no sync after 1250 bits");
                    preamble_detected = false;
                    preamble_count = 0;
                    pocbit = 0;
                }
            }
            
            if (crossing_count > 0) {
                double offset = watch_ctr - atb_ctr;
                
                if (offset > FINE_CLKT_HI) {
                    clkt -= 0.01;
                    if (clkt < (SAMPLE_RATE / BAUD_RATE) * 0.95) {
                        clkt = (SAMPLE_RATE / BAUD_RATE) * 0.95;
                    }
                } else if (offset < FINE_CLKT_LO) {
                    clkt += 0.01;
                    if (clkt > (SAMPLE_RATE / BAUD_RATE) * 1.05) {
                        clkt = (SAMPLE_RATE / BAUD_RATE) * 1.05;
                    }
                }
                
                crossing_count = 0;
            }
            
            atb_ctr += clkt;
        }
    }
}

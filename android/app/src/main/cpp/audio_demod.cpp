#include "audio_demod.h"
#include "demod.h"
#include <android/log.h>

#define LOG_TAG "AudioDemod"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)

#define SAMPLE_RATE 48000
#define BAUD_RATE 1200
#define PDW_REFERENCE_RATE 44100.0
#define FINE_CLKT_HI 1.90
#define FINE_CLKT_LO 0.32
#define ATB_CENTER 0
#define ATB_THRESHOLD 7
#define ATB_SAMPLE_OFFSET 0
#define PRE_THRESHOLD 7
#define PREAMBLE_COUNT_REQUIRED 50
#define POCBIT_BUDGET 1250

static const double watch_step = (double)SAMPLE_RATE / BAUD_RATE;
static const double preamble_window_lo = 28.0 * SAMPLE_RATE / PDW_REFERENCE_RATE;
static const double preamble_window_hi = 44.0 * SAMPLE_RATE / PDW_REFERENCE_RATE;

static double watch_ctr = -1;
static long buffer_base = 0;
static int sync_bit = 0;
static int n_samples = 0;
static int preamble_count = 0;
static int pocbit = 0;
static int atb_bit = 0;
static int atb_len = 0;

void resetAudioDemod() {
    watch_ctr = -1;
    buffer_base = 0;
    sync_bit = 0;
    n_samples = 0;
    preamble_count = 0;
    pocbit = 0;
    atb_bit = 0;
    atb_len = 0;
    LOGD("Audio demodulator reset");
}

void processAudioSamples(int16_t *samples, int size) {
    for (int i = 0; i < size; i++) {
        long atb_ctr = buffer_base + i;
        int val = samples[i] >> 8;

        n_samples++;

        bool crossing = false;
        if (val < -PRE_THRESHOLD && sync_bit == 1) {
            sync_bit = 0;
            crossing = true;
        } else if (val > PRE_THRESHOLD && sync_bit == 0) {
            sync_bit = 1;
            crossing = true;
        }

        bool locked = false;
        if (crossing && pocbit == 0) {
            if (n_samples > preamble_window_lo && n_samples < preamble_window_hi) {
                preamble_count++;
                if (preamble_count > PREAMBLE_COUNT_REQUIRED) {
                    preamble_count = 0;
                    pocbit = POCBIT_BUDGET;
                    locked = true;
                    LOGD("Preamble detected! samples=%d", n_samples);
                }
            } else {
                preamble_count = 0;
            }
            n_samples = 0;
        }
        if (locked) continue;

        atb_len++;

        if (val < ATB_CENTER - ATB_THRESHOLD && atb_bit == 1) {
            atb_bit = 0;
            if (atb_len < watch_step * 2 &&
                atb_len / watch_step > FINE_CLKT_LO &&
                atb_len / watch_step < FINE_CLKT_HI) {
                watch_ctr = atb_ctr + watch_step / 2 + ATB_SAMPLE_OFFSET;
            }
            atb_len = 0;
        } else if (val > ATB_CENTER + ATB_THRESHOLD && atb_bit == 0) {
            atb_bit = 1;
            if (atb_len < watch_step * 2 &&
                atb_len / watch_step > FINE_CLKT_LO &&
                atb_len / watch_step < FINE_CLKT_HI) {
                watch_ctr = atb_ctr + watch_step / 2 + ATB_SAMPLE_OFFSET;
            }
            atb_len = 0;
        }

        if (watch_ctr - atb_ctr < 1 && watch_ctr != -1) {
            if (pocbit > 0) {
                feedBit(demodMic, atb_bit == 1);
                pocbit--;
                if (pocbit == 0) {
                    LOGD("POCSAG timeout - no sync after %d bits", POCBIT_BUDGET);
                    resetFraming(demodMic);
                }
            }
            watch_ctr += watch_step;
        }
    }
    buffer_base += size;
}

#ifndef DEMOD_H
#define DEMOD_H

#include <complex>
#include <stdbool.h>
#include <stdint.h>
#include <string>
#include <iostream>

#include "dsp/phasediscri.h"
#include "dsp/firfilter.h"
#include "util/movingaverage.h"

#define SDR_RX_SCALED 32768.0
#define SAMPLE_RATE 48000.0
#define BAUD_RATE 1200.0
#define DEVIATION 4500.0
#define SAMPLES_PER_SYMBOL (SAMPLE_RATE / BAUD_RATE)
#define RTL_INPUT_RATE 240000.0
#define DECIMATION 5
#define POCSAG_SYNCCODE 0x7CD215D8
#define POCSAG_SYNCCODE_INV ~0x7CD215D8
#define PAGERDEMOD_POCSAG_IDLECODE 0x7A89C197
#define PAGERDEMOD_BATCH_WORDS 17
#define PAGERDEMOD_FRAMES_PER_BATCH 8
#define PAGERDEMOD_CODEWORDS_PER_FRAME 2

struct DemodState {
    PhaseDiscriminators phaseDiscri;
    Lowpass<double> lowpassBaud;
    MovingAverageUtil<double, double, 2048> preambleMovingAverage;
    Lowpass<double> decimationLowpassI;
    Lowpass<double> decimationLowpassQ;
    bool dsp_initialized = false;

    bool got_SC = false;
    double dc_offset = 0.0;
    bool prev_data = false;
    bool bit_inverted = false;
    bool data_bit = false;
    int sync_cnt = 0;
    int bit_cnt = 0;
    int word_cnt = 0;
    uint32_t bits = 0;
    uint32_t code_words[PAGERDEMOD_BATCH_WORDS] = {};
    bool code_words_bch_error[PAGERDEMOD_BATCH_WORDS] = {};
    bool hysteresis_state = false;
    double peak_pos = 0.01;
    double peak_neg = -0.01;

    bool is_message_ready = false;
    std::string numeric_msg;
    std::string alpha_msg;
    uint32_t address = 0;
    int function_bits = 0;
    uint32_t alpha_bit_buffer = 0;
    int alpha_bit_buffer_bits = 0;
    int parity_errors = 0;
    int bch_errors = 0;
    int batch_num = 0;

    double magsqRaw = 0.0;
};

extern DemodState demodMic;
extern DemodState demodRtl;

void resetDemod(DemodState &state);
void resetFraming(DemodState &state);
void feedBit(DemodState &state, bool rawData);
void processOneSample(DemodState &state, int8_t i, int8_t q);

#endif

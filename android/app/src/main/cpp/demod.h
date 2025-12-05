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
#define POCSAG_SYNCCODE 0x7CD215D8
#define POCSAG_SYNCCODE_INV ~0x7CD215D8
#define PAGERDEMOD_POCSAG_IDLECODE 0x7A89C197
#define PAGERDEMOD_BATCH_WORDS 17
#define PAGERDEMOD_FRAMES_PER_BATCH 8
#define PAGERDEMOD_CODEWORDS_PER_FRAME 2

extern bool is_message_ready;
extern std::string numeric_msg;
extern std::string alpha_msg;
extern uint32_t address;
extern int function_bits;

extern PhaseDiscriminators phaseDiscri;
extern Lowpass<double> lowpassBaud;
extern MovingAverageUtil<double, double, 2048> preambleMovingAverage;
extern double magsqRaw;

void ensureDSPInitialized();
void processOneSample(int8_t i, int8_t q);
void processBasebandSample(double sample);

#endif
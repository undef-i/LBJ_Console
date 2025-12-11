#ifndef AUDIO_DEMOD_H
#define AUDIO_DEMOD_H

#include <cstdint>

void processAudioSamples(int16_t *samples, int size);

void resetAudioDemod();

#endif

#include "demod.h"
#include <android/log.h>

DemodState demodMic;
DemodState demodRtl;

void ensureDSPInitialized(DemodState &state) {
    if (state.dsp_initialized) return;

    state.lowpassBaud.create(301, SAMPLE_RATE, BAUD_RATE * 5.0f);
    state.decimationLowpassI.create(151, RTL_INPUT_RATE, 20000.0);
    state.decimationLowpassQ.create(151, RTL_INPUT_RATE, 20000.0);
    state.phaseDiscri.setFMScaling(SAMPLE_RATE / (2.0f * DEVIATION));

    state.dsp_initialized = true;
}

void resetDemod(DemodState &state) {
    state = DemodState();
    ensureDSPInitialized(state);
}

void resetFraming(DemodState &state) {
    state.got_SC = false;
    state.bit_inverted = false;
    state.bits = 0;
    state.bit_cnt = 0;
    state.word_cnt = 0;
    state.sync_cnt = 0;
}

int pop_cnt(uint32_t cw)
{
    int cnt = 0;
    for (int i = 0; i < 32; i++)
    {
        cnt += cw & 1;
        cw = cw >> 1;
    }
    return cnt;
}

uint32_t bchEncode(const uint32_t cw)
{
    uint32_t bit = 0;
    uint32_t localCW = cw & 0xFFFFF800;
    uint32_t cwE = localCW;

    for (bit = 1; bit <= 21; bit++)
    {
        if (cwE & 0x80000000)
        {
            cwE ^= 0xED200000;
        }
        cwE <<= 1;
    }
    localCW |= (cwE >> 21);

    return localCW;
}

bool bchDecode(const uint32_t cw, uint32_t &correctedCW)
{
    uint32_t syndrome = ((bchEncode(cw) ^ cw) >> 1) & 0x3FF;

    if (syndrome == 0)
    {
        correctedCW = cw;
        return true;
    }

    uint32_t result = 0;
    uint32_t damagedCW = cw;

    for (uint32_t xbit = 0; xbit < 31; xbit++)
    {
        result <<= 1;
        if ((syndrome == 0x3B4) ||
            (syndrome == 0x26E) ||
            (syndrome == 0x359) ||
            (syndrome == 0x076) ||
            (syndrome == 0x255) ||
            (syndrome == 0x0F0) ||
            (syndrome == 0x216) ||
            (syndrome == 0x365) ||
            (syndrome == 0x068) ||
            (syndrome == 0x25A) ||
            (syndrome == 0x343) ||
            (syndrome == 0x07B) ||
            (syndrome == 0x1E7) ||
            (syndrome == 0x129) ||
            (syndrome == 0x14E) ||
            (syndrome == 0x2C9) ||
            (syndrome == 0x0BE) ||
            (syndrome == 0x231) ||
            (syndrome == 0x0C2) ||
            (syndrome == 0x20F) ||
            (syndrome == 0x0DD) ||
            (syndrome == 0x1B4) ||
            (syndrome == 0x2B4) ||
            (syndrome == 0x334) ||
            (syndrome == 0x3F4) ||
            (syndrome == 0x394) ||
            (syndrome == 0x3A4) ||
            (syndrome == 0x3BC) ||
            (syndrome == 0x3B0) ||
            (syndrome == 0x3B6) ||
            (syndrome == 0x3B5))
        {
            syndrome ^= 0x3B4;
            result |= (~damagedCW & 0x80000000) >> 30;
        }
        else
        {
            result |= (damagedCW & 0x80000000) >> 30;
        }
        damagedCW <<= 1;

        if (syndrome & 0x200)
        {
            syndrome <<= 1;
            syndrome ^= 0x769;
        }
        else
        {
            syndrome <<= 1;
        }
        syndrome &= 0x3FF;
    }

    if (syndrome != 0)
    {
        correctedCW = cw;
        return false;
    }

    correctedCW = result;
    return true;
}

int xorBits(uint32_t word, int firstBit, int lastBit)
{
    int x = 0;
    for (int i = firstBit; i <= lastBit; i++)
    {
        x ^= (word >> i) & 1;
    }
    return x;
}

bool evenParity(uint32_t word, int firstBit, int lastBit, int parityBit)
{
    return xorBits(word, firstBit, lastBit) == parityBit;
}

uint32_t reverse(uint32_t x)
{
    x = (((x & 0xaaaaaaaa) >> 1) | ((x & 0x55555555) << 1));
    x = (((x & 0xcccccccc) >> 2) | ((x & 0x33333333) << 2));
    x = (((x & 0xf0f0f0f0) >> 4) | ((x & 0x0f0f0f0f) << 4));
    x = (((x & 0xff00ff00) >> 8) | ((x & 0x00ff00ff) << 8));
    return ((x >> 16) | (x << 16));
}

void decodeBatch(DemodState &state)
{
    int i = 1;
    for (int frame = 0; frame < PAGERDEMOD_FRAMES_PER_BATCH; frame++)
    {
        for (int word = 0; word < PAGERDEMOD_CODEWORDS_PER_FRAME; word++)
        {
            bool addressCodeWord = ((state.code_words[i] >> 31) & 1) == 0;
            bool parityError = !evenParity(state.code_words[i], 1, 31, state.code_words[i] & 0x1);

            if (state.code_words[i] == PAGERDEMOD_POCSAG_IDLECODE)
            {
            }
            else if (addressCodeWord)
            {
                state.function_bits = (state.code_words[i] >> 11) & 0x3;
                int addressBits = (state.code_words[i] >> 13) & 0x3ffff;
                state.address = (addressBits << 3) | frame;

                __android_log_print(ANDROID_LOG_DEBUG, "DEMOD", "addr_cw: raw=0x%08X addr=%u func=%d frame=%d bch_err=%d parity_err=%d",
                    state.code_words[i], state.address, state.function_bits, frame, state.code_words_bch_error[i] ? 1 : 0, parityError ? 1 : 0);

                state.numeric_msg = "";
                state.alpha_msg = "";
                state.alpha_bit_buffer_bits = 0;
                state.alpha_bit_buffer = 0;
                state.parity_errors = parityError ? 1 : 0;
                state.bch_errors = state.code_words_bch_error[i] ? 1 : 0;
            }
            else
            {
                int messageBits = (state.code_words[i] >> 11) & 0xfffff;
                if (parityError) state.parity_errors++;
                if (state.code_words_bch_error[i]) state.bch_errors++;

                __android_log_print(ANDROID_LOG_DEBUG, "DEMOD", "msg_cw: raw=0x%08X msgbits=0x%05X bch_err=%d parity_err=%d",
                    state.code_words[i], messageBits, state.code_words_bch_error[i] ? 1 : 0, parityError ? 1 : 0);

                for (int j = 16; j >= 0; j -= 4)
                {
                    uint32_t numericBits = (messageBits >> j) & 0xf;
                    numericBits = reverse(numericBits) >> (32 - 4);
                    const char numericChars[] = {
                        '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '.', 'U', ' ', '-', ')', '('};
                    char numericChar = numericChars[numericBits];
                    state.numeric_msg.push_back(numericChar);
                }

                state.alpha_bit_buffer = (state.alpha_bit_buffer << 20) | messageBits;
                state.alpha_bit_buffer_bits += 20;
                while (state.alpha_bit_buffer_bits >= 8)
                {
                    unsigned char c = (state.alpha_bit_buffer >> (state.alpha_bit_buffer_bits - 8)) & 0xff;
                    c = reverse(c) >> (32 - 8);
                    if (c != 0 && c != 0x3 && c != 0x4)
                    {
                        state.alpha_msg.push_back(c);
                    }
                    state.alpha_bit_buffer_bits -= 8;
                    if (state.alpha_bit_buffer_bits == 0)
                    {
                        state.alpha_bit_buffer = 0;
                    }
                    else
                    {
                        state.alpha_bit_buffer &= (1 << state.alpha_bit_buffer_bits) - 1;
                    }
                }
            }
            i++;
        }
    }
}

void feedBit(DemodState &state, bool rawData)
{
    state.data_bit = state.bit_inverted ? rawData : !rawData;

    state.bits = (state.bits << 1) | (state.data_bit ? 1 : 0);
    state.bit_cnt++;

    if (state.bit_cnt > 32) state.bit_cnt = 32;

    if (state.bit_cnt == 32 && !state.got_SC)
    {
        if (state.bits == POCSAG_SYNCCODE)
        {
            state.got_SC = true;
            state.bit_inverted = false;
        }
        else if (state.bits == POCSAG_SYNCCODE_INV)
        {
            state.got_SC = true;
            state.bit_inverted = true;
        }
        else if (pop_cnt(state.bits ^ POCSAG_SYNCCODE) <= 3)
        {
            uint32_t corrected_cw;
            if (bchDecode(state.bits, corrected_cw) && corrected_cw == POCSAG_SYNCCODE)
            {
                state.got_SC = true;
                state.bit_inverted = false;
            }
        }
        else if (pop_cnt(state.bits ^ POCSAG_SYNCCODE_INV) <= 3)
        {
            uint32_t corrected_cw;
            if (bchDecode(~state.bits, corrected_cw) && corrected_cw == POCSAG_SYNCCODE)
            {
                state.got_SC = true;
                state.bit_inverted = true;
            }
        }

        if (state.got_SC)
        {
            __android_log_print(ANDROID_LOG_DEBUG, "DEMOD", "sync_found: inverted=%d bits=0x%08X", state.bit_inverted ? 1 : 0, state.bits);
            state.bits = 0;
            state.bit_cnt = 0;
            state.code_words[0] = POCSAG_SYNCCODE;
            state.word_cnt = 1;
        }
    }
    else if (state.bit_cnt == 32 && state.got_SC)
    {
        uint32_t corrected_cw;
        state.code_words_bch_error[state.word_cnt] = !bchDecode(state.bits, corrected_cw);
        state.code_words[state.word_cnt] = corrected_cw;
        state.word_cnt++;

        if (state.word_cnt == 1 && corrected_cw != POCSAG_SYNCCODE)
        {
            state.got_SC = false;
            state.bit_inverted = false;
        }

        if (state.word_cnt == PAGERDEMOD_BATCH_WORDS)
        {
            decodeBatch(state);
            state.batch_num++;
            state.word_cnt = 0;
        }

        state.bits = 0;
        state.bit_cnt = 0;

        if (state.address > 0 && !state.numeric_msg.empty())
        {
            state.is_message_ready = true;
        }
    }
}

void processOneSample(DemodState &state, int8_t i, int8_t q)
{
    ensureDSPInitialized(state);

    float fi = ((float)i) / 128.0f;
    float fq = ((float)q) / 128.0f;

    std::complex<float> iq(fi, fq);

    float deviation;
    double fmDemod = state.phaseDiscri.phaseDiscriminatorDelta(iq, state.magsqRaw, deviation);

    double filt = state.lowpassBaud.filter(fmDemod);

    if (!state.got_SC) {
        state.preambleMovingAverage(filt);
        state.dc_offset = state.preambleMovingAverage.asDouble();
    }

    double sample_val = filt - state.dc_offset;

    if (sample_val > state.peak_pos) state.peak_pos = sample_val;
    else state.peak_pos *= 0.9999;

    if (sample_val < state.peak_neg) state.peak_neg = sample_val;
    else state.peak_neg *= 0.9999;

    double threshold = (state.peak_pos - state.peak_neg) * 0.15;
    if (threshold < 0.005) threshold = 0.005;

    if (sample_val > threshold)
    {
        state.hysteresis_state = true;
    }
    else if (sample_val < -threshold)
    {
        state.hysteresis_state = false;
    }

    bool data = state.hysteresis_state;

    if (data != state.prev_data) {
        state.sync_cnt = SAMPLES_PER_SYMBOL / 2;
    } else {
        state.sync_cnt--;

        if (state.sync_cnt <= 0) {
            feedBit(state, data);
            state.sync_cnt = SAMPLES_PER_SYMBOL;
        }
    }

    state.prev_data = data;
}

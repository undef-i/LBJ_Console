#include "demod.h"
#include <android/log.h>

bool is_message_ready = false;

PhaseDiscriminators phaseDiscri;
Lowpass<double> lowpassBaud;
MovingAverageUtil<double, double, 2048> preambleMovingAverage;

bool got_SC = false;
double dc_offset = 0.0;
bool prev_data, bit_inverted, data_bit;
int sync_cnt, bit_cnt = 0, word_cnt = 0;
uint32_t bits;
uint32_t code_words[PAGERDEMOD_BATCH_WORDS];
bool code_words_bch_error[PAGERDEMOD_BATCH_WORDS];

static bool hysteresis_state = false;
static bool dsp_initialized = false;

std::string numeric_msg, alpha_msg;
int function_bits;
uint32_t address;
uint32_t alpha_bit_buffer;
int alpha_bit_buffer_bits;
int parity_errors;
int bch_errors;
int batch_num;

double magsqRaw;

void ensureDSPInitialized() {
    if (dsp_initialized) return;
    
    lowpassBaud.create(301, SAMPLE_RATE, BAUD_RATE * 5.0f);
    phaseDiscri.setFMScaling(SAMPLE_RATE / (2.0f * DEVIATION));
    
    dsp_initialized = true;
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

void decodeBatch()
{
    int i = 1;
    for (int frame = 0; frame < PAGERDEMOD_FRAMES_PER_BATCH; frame++)
    {
        for (int word = 0; word < PAGERDEMOD_CODEWORDS_PER_FRAME; word++)
        {
            bool addressCodeWord = ((code_words[i] >> 31) & 1) == 0;
            bool parityError = !evenParity(code_words[i], 1, 31, code_words[i] & 0x1);

            if (code_words[i] == PAGERDEMOD_POCSAG_IDLECODE)
            {
            }
            else if (addressCodeWord)
            {
                function_bits = (code_words[i] >> 11) & 0x3;
                int addressBits = (code_words[i] >> 13) & 0x3ffff;
                address = (addressBits << 3) | frame;
                
                __android_log_print(ANDROID_LOG_DEBUG, "DEMOD", "addr_cw: raw=0x%08X addr=%u func=%d frame=%d bch_err=%d parity_err=%d",
                    code_words[i], address, function_bits, frame, code_words_bch_error[i] ? 1 : 0, parityError ? 1 : 0);
                
                numeric_msg = "";
                alpha_msg = "";
                alpha_bit_buffer_bits = 0;
                alpha_bit_buffer = 0;
                parity_errors = parityError ? 1 : 0;
                bch_errors = code_words_bch_error[i] ? 1 : 0;
            }
            else
            {
                int messageBits = (code_words[i] >> 11) & 0xfffff;
                if (parityError) parity_errors++;
                if (code_words_bch_error[i]) bch_errors++;
                
                __android_log_print(ANDROID_LOG_DEBUG, "DEMOD", "msg_cw: raw=0x%08X msgbits=0x%05X bch_err=%d parity_err=%d",
                    code_words[i], messageBits, code_words_bch_error[i] ? 1 : 0, parityError ? 1 : 0);

                for (int j = 16; j >= 0; j -= 4)
                {
                    uint32_t numericBits = (messageBits >> j) & 0xf;
                    numericBits = reverse(numericBits) >> (32 - 4);
                    const char numericChars[] = {
                        '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '.', 'U', ' ', '-', ')', '('};
                    char numericChar = numericChars[numericBits];
                    numeric_msg.push_back(numericChar);
                }

                alpha_bit_buffer = (alpha_bit_buffer << 20) | messageBits;
                alpha_bit_buffer_bits += 20;
                while (alpha_bit_buffer_bits >= 8)
                {
                    unsigned char c = (alpha_bit_buffer >> (alpha_bit_buffer_bits - 8)) & 0xff;
                    c = reverse(c) >> (32 - 8);
                    if (c != 0 && c != 0x3 && c != 0x4)
                    {
                        alpha_msg.push_back(c);
                    }
                    alpha_bit_buffer_bits -= 8;
                    if (alpha_bit_buffer_bits == 0)
                    {
                        alpha_bit_buffer = 0;
                    }
                    else
                    {
                        alpha_bit_buffer &= (1 << alpha_bit_buffer_bits) - 1;
                    }
                }
            }
            i++;
        }
    }
}

void processBasebandSample(double sample)
{
    ensureDSPInitialized();

    double filt = lowpassBaud.filter(sample);

    if (!got_SC)
    {
        preambleMovingAverage(filt);
        dc_offset = preambleMovingAverage.asDouble();
    }

    double sample_val = filt - dc_offset;

    static double peak_pos = 0.01;
    static double peak_neg = -0.01;
    
    if (sample_val > peak_pos) peak_pos = sample_val;
    else peak_pos *= 0.9999;
    
    if (sample_val < peak_neg) peak_neg = sample_val;
    else peak_neg *= 0.9999;
    
    double threshold = (peak_pos - peak_neg) * 0.15;
    if (threshold < 0.005) threshold = 0.005;
    
    if (sample_val > threshold) 
    {
        hysteresis_state = true;
    }
    else if (sample_val < -threshold) 
    {
        hysteresis_state = false;
    }

    bool data = hysteresis_state;

    if (data != prev_data)
    {
        sync_cnt = SAMPLES_PER_SYMBOL / 2; 
    }
    else
    {
        sync_cnt--; 

        if (sync_cnt <= 0)
        {
            if (bit_inverted) data_bit = data;
            else data_bit = !data;

            bits = (bits << 1) | data_bit;
            bit_cnt++;

            if (bit_cnt > 32) bit_cnt = 32;

            if (bit_cnt == 32 && !got_SC)
            {
                if (bits == POCSAG_SYNCCODE)
                {
                    got_SC = true;
                    bit_inverted = false;
                }
                else if (bits == POCSAG_SYNCCODE_INV)
                {
                    got_SC = true;
                    bit_inverted = true;
                }
                else if (pop_cnt(bits ^ POCSAG_SYNCCODE) <= 3)
                {
                    uint32_t corrected_cw;
                    if (bchDecode(bits, corrected_cw) && corrected_cw == POCSAG_SYNCCODE)
                    {
                        got_SC = true;
                        bit_inverted = false;
                    }
                }
                else if (pop_cnt(bits ^ POCSAG_SYNCCODE_INV) <= 3)
                {
                    uint32_t corrected_cw;
                    if (bchDecode(~bits, corrected_cw) && corrected_cw == POCSAG_SYNCCODE)
                    {
                        got_SC = true;
                        bit_inverted = true;
                    }
                }

                if (got_SC)
                {
                    __android_log_print(ANDROID_LOG_DEBUG, "DEMOD", "sync_found: inverted=%d bits=0x%08X", bit_inverted ? 1 : 0, bits);
                    bits = 0;
                    bit_cnt = 0;
                    code_words[0] = POCSAG_SYNCCODE;
                    word_cnt = 1;
                }
            }
            else if (bit_cnt == 32 && got_SC)
            {
                uint32_t corrected_cw;
                code_words_bch_error[word_cnt] = !bchDecode(bits, corrected_cw);
                code_words[word_cnt] = corrected_cw;
                word_cnt++;

                if (word_cnt == 1 && corrected_cw != POCSAG_SYNCCODE)
                {
                    got_SC = false;
                    bit_inverted = false;
                }

                if (word_cnt == PAGERDEMOD_BATCH_WORDS)
                {
                    decodeBatch();
                    batch_num++;
                    word_cnt = 0;
                }

                bits = 0;
                bit_cnt = 0;

                if (address > 0 && !numeric_msg.empty())
                {
                    is_message_ready = true;
                }
                else
                {
                    is_message_ready = false;
                }
            }

            sync_cnt = SAMPLES_PER_SYMBOL;
        }
    }

    prev_data = data;
}

void processOneSample(int8_t i, int8_t q)
{
    float fi = ((float)i) / 128.0f;
    float fq = ((float)q) / 128.0f;

    std::complex<float> iq(fi, fq);

    float deviation;
    double fmDemod = phaseDiscri.phaseDiscriminatorDelta(iq, magsqRaw, deviation);
    
    double filt = lowpassBaud.filter(fmDemod);

    if (!got_SC) {
        preambleMovingAverage(filt);
        dc_offset = preambleMovingAverage.asDouble();
    }

    bool data = (filt - dc_offset) >= 0.0;

    if (data != prev_data) {
        sync_cnt = SAMPLES_PER_SYMBOL / 2;
    } else {
        sync_cnt--;
        
        if (sync_cnt <= 0) {
            if (bit_inverted) {
                data_bit = data;
            } else {
                data_bit = !data;
            }

            bits = (bits << 1) | data_bit;
            bit_cnt++;

            if (bit_cnt > 32) {
                bit_cnt = 32;
            }

            if (bit_cnt == 32 && !got_SC) {
                if (bits == POCSAG_SYNCCODE) {
                    got_SC = true;
                    bit_inverted = false;
                } else if (bits == POCSAG_SYNCCODE_INV) {
                    got_SC = true;
                    bit_inverted = true;
                } else if (pop_cnt(bits ^ POCSAG_SYNCCODE) <= 3) {
                    uint32_t corrected_cw;
                    if (bchDecode(bits, corrected_cw) && corrected_cw == POCSAG_SYNCCODE) {
                        got_SC = true;
                        bit_inverted = false;
                    }
                } else if (pop_cnt(bits ^ POCSAG_SYNCCODE_INV) <= 3) {
                    uint32_t corrected_cw;
                    if (bchDecode(~bits, corrected_cw) && corrected_cw == POCSAG_SYNCCODE) {
                        got_SC = true;
                        bit_inverted = true;
                    }
                }

                if (got_SC) {
                    __android_log_print(ANDROID_LOG_DEBUG, "DEMOD", "sync_found: inverted=%d bits=0x%08X", bit_inverted ? 1 : 0, bits);
                    bits = 0;
                    bit_cnt = 0;
                    code_words[0] = POCSAG_SYNCCODE;
                    word_cnt = 1;
                }
            } else if (bit_cnt == 32 && got_SC) {
                uint32_t corrected_cw;
                code_words_bch_error[word_cnt] = !bchDecode(bits, corrected_cw);
                code_words[word_cnt] = corrected_cw;
                word_cnt++;

                if (word_cnt == 1 && corrected_cw != POCSAG_SYNCCODE) {
                    got_SC = false;
                    bit_inverted = false;
                }

                if (word_cnt == PAGERDEMOD_BATCH_WORDS) {
                    decodeBatch();
                    batch_num++;
                    word_cnt = 0;
                }

                bits = 0;
                bit_cnt = 0;

                if (address > 0 && !numeric_msg.empty()) {
                    is_message_ready = true;
                }
            }

            sync_cnt = SAMPLES_PER_SYMBOL;
        }
    }

    prev_data = data;
}
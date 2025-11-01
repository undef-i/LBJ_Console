#include "demod.h"

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

std::string numeric_msg, alpha_msg;
int function_bits;
uint32_t address;
uint32_t alpha_bit_buffer; // Bit buffer to 7-bit chars spread across codewords
int alpha_bit_buffer_bits; // Count of bits in alpha_bit_buffer
int parity_errors;         // Count of parity errors in current message
int bch_errors;            // Count of BCH errors in current message
int batch_num;             // Count of batches in current transmission

double magsqRaw;

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
    uint32_t localCW = cw & 0xFFFFF800; // Mask off BCH parity and even parity bits
    uint32_t cwE = localCW;

    // Calculate BCH bits
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

// Use BCH decoding to try to fix any bit errors
// Returns true if able to be decode/repair successful
// See: https://www.eevblog.com/forum/microcontrollers/practical-guides-to-bch-fec/
bool bchDecode(const uint32_t cw, uint32_t &correctedCW)
{
    // Calculate syndrome
    // We do this by recalculating the BCH parity bits and XORing them against the received ones
    uint32_t syndrome = ((bchEncode(cw) ^ cw) >> 1) & 0x3FF;

    if (syndrome == 0)
    {
        // Syndrome of zero indicates no repair required
        correctedCW = cw;
        return true;
    }

    // Meggitt decoder

    uint32_t result = 0;
    uint32_t damagedCW = cw;

    // Calculate BCH bits
    for (uint32_t xbit = 0; xbit < 31; xbit++)
    {
        // Produce the next corrected bit in the high bit of the result
        result <<= 1;
        if ((syndrome == 0x3B4) || // 0x3B4: Syndrome when a single error is detected in the MSB
            (syndrome == 0x26E) || // 0x26E: Two adjacent errors
            (syndrome == 0x359) || // 0x359: Two errors, one OK bit between
            (syndrome == 0x076) || // 0x076: Two errors, two OK bits between
            (syndrome == 0x255) || // 0x255: Two errors, three OK bits between
            (syndrome == 0x0F0) || // 0x0F0: Two errors, four OK bits between
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
            // Syndrome matches an error in the MSB
            // Correct that error and adjust the syndrome to account for it
            syndrome ^= 0x3B4;
            result |= (~damagedCW & 0x80000000) >> 30;
        }
        else
        {
            // No error
            result |= (damagedCW & 0x80000000) >> 30;
        }
        damagedCW <<= 1;

        // Handle syndrome shift register feedback
        if (syndrome & 0x200)
        {
            syndrome <<= 1;
            syndrome ^= 0x769; // 0x769 = POCSAG generator polynomial -- x^10 + x^9 + x^8 + x^6 + x^5 + x^3 + 1
        }
        else
        {
            syndrome <<= 1;
        }
        // Mask off bits which fall off the end of the syndrome shift register
        syndrome &= 0x3FF;
    }

    // Check if error correction was successful
    if (syndrome != 0)
    {
        // Syndrome nonzero at end indicates uncorrectable errors
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

// Check for even parity
bool evenParity(uint32_t word, int firstBit, int lastBit, int parityBit)
{
    return xorBits(word, firstBit, lastBit) == parityBit;
}

// Reverse order of bits
uint32_t reverse(uint32_t x)
{
    x = (((x & 0xaaaaaaaa) >> 1) | ((x & 0x55555555) << 1));
    x = (((x & 0xcccccccc) >> 2) | ((x & 0x33333333) << 2));
    x = (((x & 0xf0f0f0f0) >> 4) | ((x & 0x0f0f0f0f) << 4));
    x = (((x & 0xff00ff00) >> 8) | ((x & 0x00ff00ff) << 8));
    return ((x >> 16) | (x << 16));
}

// Decode a batch of codewords to addresses and messages
// Messages may be spreadout over multiple batches
// https://www.itu.int/dms_pubrec/itu-r/rec/m/R-REC-M.584-1-198607-S!!PDF-E.pdf
// https://www.itu.int/dms_pubrec/itu-r/rec/m/R-REC-M.584-2-199711-I!!PDF-E.pdf
void decodeBatch()
{
    int i = 1;
    for (int frame = 0; frame < PAGERDEMOD_FRAMES_PER_BATCH; frame++)
    {
        for (int word = 0; word < PAGERDEMOD_CODEWORDS_PER_FRAME; word++)
        {
            bool addressCodeWord = ((code_words[i] >> 31) & 1) == 0;

            // Check parity bit
            bool parityError = !evenParity(code_words[i], 1, 31, code_words[i] & 0x1);

            if (code_words[i] == PAGERDEMOD_POCSAG_IDLECODE)
            {
                // Idle
            }
            else if (addressCodeWord)
            {
                // Address
                function_bits = (code_words[i] >> 11) & 0x3;
                int addressBits = (code_words[i] >> 13) & 0x3ffff;
                address = (addressBits << 3) | frame;
                numeric_msg = "";
                alpha_msg = "";
                alpha_bit_buffer_bits = 0;
                alpha_bit_buffer = 0;
                parity_errors = parityError ? 1 : 0;
                bch_errors = code_words_bch_error[i] ? 1 : 0;
            }
            else
            {
                // Message - decode as both numeric and ASCII - not all operators use functionBits to indidcate encoding
                int messageBits = (code_words[i] >> 11) & 0xfffff;
                if (parityError)
                {
                    parity_errors++;
                }
                if (code_words_bch_error[i])
                {
                    bch_errors++;
                }

                // Numeric format
                for (int j = 16; j >= 0; j -= 4)
                {
                    uint32_t numericBits = (messageBits >> j) & 0xf;
                    numericBits = reverse(numericBits) >> (32 - 4);
                    // Spec has 0xa as 'spare', but other decoders treat is as .
                    const char numericChars[] = {
                        '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '.', 'U', ' ', '-', ')', '('};
                    char numericChar = numericChars[numericBits];
                    numeric_msg.push_back(numericChar);
                }

                // 7-bit ASCII alpnanumeric format
                alpha_bit_buffer = (alpha_bit_buffer << 20) | messageBits;
                alpha_bit_buffer_bits += 20;
                while (alpha_bit_buffer_bits >= 7)
                {
                    // Extract next 7-bit character from bit buffer
                    char c = (alpha_bit_buffer >> (alpha_bit_buffer_bits - 7)) & 0x7f;
                    // Reverse bit ordering
                    c = reverse(c) >> (32 - 7);
                    // Add to received message string (excluding, null, end of text, end ot transmission)
                    if (c != 0 && c != 0x3 && c != 0x4)
                    {
                        alpha_msg.push_back(c);
                    }
                    // Remove from bit buffer
                    alpha_bit_buffer_bits -= 7;
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

            // Move to next codeword
            i++;
        }
    }
}

void processOneSample(int8_t i, int8_t q)
{
    float fi = ((float)i) / 128.0f;
    float fq = ((float)q) / 128.0f;

    std::complex<float> iq(fi, fq);

    float deviation;
    double fmDemod = phaseDiscri.phaseDiscriminatorDelta(iq, magsqRaw, deviation);
    // printf("fmDemod: %.3f\n", fmDemod);

    double filt = lowpassBaud.filter(fmDemod);

    if (!got_SC)
    {
        preambleMovingAverage(filt);
        dc_offset = preambleMovingAverage.asDouble();
    }

    bool data = (filt - dc_offset) >= 0.0;
    // printf("filt - dc: %.3f\n", filt - dc_offset);

    if (data != prev_data)
    {
        sync_cnt = SAMPLES_PER_SYMBOL / 2; // reset
    }
    else
    {
        sync_cnt--; // wait until next bit's midpoint

        if (sync_cnt <= 0)
        {
            if (bit_inverted)
            {
                data_bit = data;
            }
            else
            {
                data_bit = !data;
            }

            // printf("%d", data_bit);

            bits = (bits << 1) | data_bit;
            bit_cnt++;

            if (bit_cnt > 32)
            {
                bit_cnt = 32;
            }

            if (bit_cnt == 32 && !got_SC)
            {
                // printf("pop count:     %d\n", pop_cnt(bits ^ POCSAG_SYNCCODE));
                // printf("pop count inv: %d\n", pop_cnt(bits ^ POCSAG_SYNCCODE_INV));

                if (bits == POCSAG_SYNCCODE)
                {
                    got_SC = true;
                    bit_inverted = false;
                    printf("\nSync code found\n");
                }
                else if (bits == POCSAG_SYNCCODE_INV)
                {
                    got_SC = true;
                    bit_inverted = true;
                    printf("\nSync code found\n");
                }
                else if (pop_cnt(bits ^ POCSAG_SYNCCODE) <= 3)
                {
                    uint32_t corrected_cw;
                    if (bchDecode(bits, corrected_cw) && corrected_cw == POCSAG_SYNCCODE)
                    {
                        got_SC = true;
                        bit_inverted = false;
                        printf("\nSync code found\n");
                    }
                    // else printf("\nSync code not found\n");
                }
                else if (pop_cnt(bits ^ POCSAG_SYNCCODE_INV) <= 3)
                {
                    uint32_t corrected_cw;
                    if (bchDecode(~bits, corrected_cw) && corrected_cw == POCSAG_SYNCCODE)
                    {
                        got_SC = true;
                        bit_inverted = true;
                        printf("\nSync code found\n");
                    }
                    // else printf("\nSync code not found\n");
                }

                if (got_SC)
                {
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
                    printf("Addr: %d | Numeric: %s | Alpha: %s\n", address, numeric_msg.c_str(), alpha_msg.c_str());
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

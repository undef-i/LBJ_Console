import 'dart:math' as math;
import 'dart:typed_data';

final _f32Box = Float32List(1);

double _f32(double v) {
  _f32Box[0] = v;
  return _f32Box[0];
}

class FirFilter {
  FirFilter(int nTaps, double sampleRate, double cutoff) {
    if (nTaps & 1 == 0) nTaps++;
    _n = nTaps;
    _samples = Float64List(2 * nTaps);
    final halfTaps = nTaps ~/ 2 + 1;
    final taps = Float32List(halfTaps);
    final wc = 2.0 * math.pi * cutoff / sampleRate;
    for (var i = 0; i < halfTaps; i++) {
      double t;
      if (i == halfTaps - 1) {
        t = wc / math.pi;
      } else {
        final n = i - (nTaps - 1) ~/ 2;
        t = math.sin(n * wc) / (n * math.pi);
      }
      final n = i - (nTaps - 1) ~/ 2;
      t *= 0.42 +
          0.5 * math.cos(2.0 * math.pi * n / nTaps) +
          0.08 * math.cos(4.0 * math.pi * n / nTaps);
      taps[i] = t;
    }
    var sum = 0.0;
    for (var i = 0; i < taps.length - 1; i++) {
      sum = _f32(sum + taps[i] * 2.0);
    }
    sum = _f32(sum + taps[taps.length - 1]);
    for (var i = 0; i < taps.length; i++) {
      taps[i] = taps[i] / sum;
    }
    _taps = taps;
  }

  late final Float64List _samples;
  late final Float32List _taps;
  var _n = 0;
  var _ptr = 0;
}

class _PhaseDiscriminator {
  var _fmScaling = 1.0;
  var _prevArg = 0.0;

  void setFMScaling(double v) {
    _fmScaling = _f32(v);
  }

  double _atan2Approx2(double y, double x) {
    const piF = 3.1415927410125732421875;
    const piBy2F = 1.57079637050628662109375;
    if (x == 0.0) {
      if (y > 0.0) return piBy2F;
      if (y == 0.0) return 0.0;
      return -piBy2F;
    }
    double atan;
    final z = _f32(y / x);
    if (z.abs() < 1.0) {
      atan = _f32(z / _f32(1.0 + _f32(0.28 * _f32(z * z))));
      if (x < 0.0) {
        if (y < 0.0) return _f32(atan - piF);
        return _f32(atan + piF);
      }
    } else {
      atan = _f32(piBy2F - _f32(z / _f32(_f32(z * z) + 0.28)));
      if (y < 0.0) return _f32(atan - piF);
    }
    return atan;
  }

  (double, double) delta(double fltI, double fltQ) {
    final magsq = _f32(_f32(fltI * fltI) + _f32(fltQ * fltQ));
    final curArg = _atan2Approx2(fltQ, fltI);
    var fmDev = _f32(_f32(curArg - _prevArg) / math.pi);
    _prevArg = curArg;
    if (fmDev < -1.0) {
      fmDev = _f32(fmDev + 2.0);
    } else if (fmDev > 1.0) {
      fmDev = _f32(fmDev - 2.0);
    }
    return (_f32(fmDev * _fmScaling), magsq);
  }
}

class _MovingAverage2048 {
  final _samples = Float64List(2048);
  var _numSamples = 0;
  var _index = 0;
  var _total = 0.0;

  void reset() {
    _samples.fillRange(0, 2048, 0.0);
    _numSamples = 0;
    _index = 0;
    _total = 0.0;
  }

  void call(double sample) {
    if (_numSamples < 2048) {
      _samples[_numSamples++] = sample;
      _total += sample;
    } else {
      final oldest = _samples[_index];
      _total += sample - oldest;
      _samples[_index] = sample;
      _index = (_index + 1) % 2048;
    }
  }

  double asDouble() => _total / 2048;
}

const _syncCode = 0x7CD215D8;
const _syncCodeInv = (~_syncCode) & 0xFFFFFFFF;
const _idleCode = 0x7A89C197;
const _batchWords = 17;

int _popCnt(int cw) {
  var cnt = 0;
  for (var i = 0; i < 32; i++) {
    cnt += cw & 1;
    cw = cw >> 1;
  }
  return cnt;
}

int _bchEncode(int cw) {
  var cwE = cw & 0xFFFFF800;
  var localCW = cwE;
  for (var bit = 1; bit <= 21; bit++) {
    if (cwE & 0x80000000 != 0) {
      cwE ^= 0xED200000;
    }
    cwE = (cwE << 1) & 0xFFFFFFFF;
  }
  localCW |= cwE >> 21;
  return localCW;
}

(int, bool) _bchDecode(int cw) {
  var syndrome = ((_bchEncode(cw) ^ cw) >> 1) & 0x3FF;
  if (syndrome == 0) return (cw, true);
  var result = 0;
  var damagedCW = cw;
  for (var xbit = 0; xbit < 31; xbit++) {
    result = (result << 1) & 0xFFFFFFFF;
    const syndromes = {
      0x3B4, 0x26E, 0x359, 0x076, 0x255, 0x0F0, 0x216, 0x365, 0x068, 0x25A,
      0x343, 0x07B, 0x1E7, 0x129, 0x14E, 0x2C9, 0x0BE, 0x231, 0x0C2, 0x20F,
      0x0DD, 0x1B4, 0x2B4, 0x334, 0x3F4, 0x394, 0x3A4, 0x3BC, 0x3B0, 0x3B6,
      0x3B5,
    };
    if (syndromes.contains(syndrome)) {
      syndrome ^= 0x3B4;
      result |= ((~damagedCW) & 0x80000000) >> 30;
    } else {
      result |= (damagedCW & 0x80000000) >> 30;
    }
    damagedCW = (damagedCW << 1) & 0xFFFFFFFF;
    if (syndrome & 0x200 != 0) {
      syndrome = (syndrome << 1) ^ 0x769;
    } else {
      syndrome = syndrome << 1;
    }
    syndrome &= 0x3FF;
  }
  if (syndrome != 0) return (cw, false);
  return (result, true);
}

int _xorBits(int word, int firstBit, int lastBit) {
  var x = 0;
  for (var i = firstBit; i <= lastBit; i++) {
    x ^= (word >> i) & 1;
  }
  return x;
}

int _reverse32(int x) {
  x = ((x & 0xAAAAAAAA) >> 1) | ((x & 0x55555555) << 1);
  x = ((x & 0xCCCCCCCC) >> 2) | ((x & 0x33333333) << 2);
  x = ((x & 0xF0F0F0F0) >> 4) | ((x & 0x0F0F0F0F) << 4);
  x = ((x & 0xFF00FF00) >> 8) | ((x & 0x00FF00FF) << 8);
  return ((x >> 16) | ((x << 16) & 0xFFFFFFFF)) & 0xFFFFFFFF;
}

class PocsagMessage {
  PocsagMessage(this.address, this.function, this.content);
  final int address;
  final int function;
  final String content;
  String get wire => '[MSG]$address|$function|$content';
}

class PocsagFraming {
  var gotSC = false;
  var bitInverted = false;
  var dataBit = false;
  var bitCnt = 0;
  var wordCnt = 0;
  var bits = 0;
  final codeWords = Int32List(_batchWords);
  final codeWordsBchError = List<bool>.filled(_batchWords, false);
  var isMessageReady = false;
  var numericMsg = '';
  var alphaMsg = '';
  var address = 0;
  var functionBits = 0;
  var alphaBitBuffer = 0;
  var alphaBitBufferBits = 0;
  var parityErrors = 0;
  var bchErrors = 0;
  var batchNum = 0;

  void resetFraming() {
    gotSC = false;
    bitInverted = false;
    bits = 0;
    bitCnt = 0;
    wordCnt = 0;
  }

  void _decodeBatch() {
    var i = 1;
    for (var frame = 0; frame < 8; frame++) {
      for (var word = 0; word < 2; word++) {
        final cw = codeWords[i] & 0xFFFFFFFF;
        final addressCodeWord = ((cw >> 31) & 1) == 0;
        final parityError = _xorBits(cw, 1, 31) != (cw & 0x1);
        if (cw == _idleCode) {
        } else if (addressCodeWord) {
          functionBits = (cw >> 11) & 0x3;
          final addressBits = (cw >> 13) & 0x3FFFF;
          address = (addressBits << 3) | frame;
          numericMsg = '';
          alphaMsg = '';
          alphaBitBufferBits = 0;
          alphaBitBuffer = 0;
          parityErrors = parityError ? 1 : 0;
          bchErrors = codeWordsBchError[i] ? 1 : 0;
        } else {
          final messageBits = (cw >> 11) & 0xFFFFF;
          if (parityError) parityErrors++;
          if (codeWordsBchError[i]) bchErrors++;
          const numericChars = [
            '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '.', 'U', ' ', '-',
            ')', '(',
          ];
          final sb = StringBuffer(numericMsg);
          for (var j = 16; j >= 0; j -= 4) {
            final numericBits = (messageBits >> j) & 0xF;
            final idx = _reverse32(numericBits) >> 28;
            sb.write(numericChars[idx]);
          }
          numericMsg = sb.toString();
          alphaBitBuffer =
              ((alphaBitBuffer << 20) | messageBits) & 0xFFFFFFFF;
          alphaBitBufferBits += 20;
          final asb = StringBuffer(alphaMsg);
          while (alphaBitBufferBits >= 8) {
            var c = (alphaBitBuffer >> (alphaBitBufferBits - 8)) & 0xFF;
            c = _reverse32(c) >> 24;
            if (c != 0 && c != 0x3 && c != 0x4) {
              asb.writeCharCode(c);
            }
            alphaBitBufferBits -= 8;
            if (alphaBitBufferBits == 0) {
              alphaBitBuffer = 0;
            } else {
              alphaBitBuffer &= (1 << alphaBitBufferBits) - 1;
            }
          }
          alphaMsg = asb.toString();
        }
        i++;
      }
    }
  }

  void feedBit(bool rawData) {
    dataBit = bitInverted ? rawData : !rawData;
    bits = ((bits << 1) | (dataBit ? 1 : 0)) & 0xFFFFFFFF;
    bitCnt++;
    if (bitCnt > 32) bitCnt = 32;

    if (bitCnt == 32 && !gotSC) {
      if (bits == _syncCode) {
        gotSC = true;
        bitInverted = false;
      } else if (bits == _syncCodeInv) {
        gotSC = true;
        bitInverted = true;
      } else if (_popCnt(bits ^ _syncCode) <= 3) {
        final (corrected, ok) = _bchDecode(bits);
        if (ok && corrected == _syncCode) {
          gotSC = true;
          bitInverted = false;
        }
      } else if (_popCnt(bits ^ _syncCodeInv) <= 3) {
        final (corrected, ok) = _bchDecode((~bits) & 0xFFFFFFFF);
        if (ok && corrected == _syncCode) {
          gotSC = true;
          bitInverted = true;
        }
      }
      if (gotSC) {
        bits = 0;
        bitCnt = 0;
        codeWords[0] = _syncCode;
        wordCnt = 1;
      }
    } else if (bitCnt == 32 && gotSC) {
      final (correctedCw, ok) = _bchDecode(bits);
      codeWordsBchError[wordCnt] = !ok;
      codeWords[wordCnt] = correctedCw;
      wordCnt++;
      if (wordCnt == 1 && correctedCw != _syncCode) {
        gotSC = false;
        bitInverted = false;
      }
      if (wordCnt == _batchWords) {
        _decodeBatch();
        batchNum++;
        wordCnt = 0;
      }
      bits = 0;
      bitCnt = 0;
      if (address > 0 && numericMsg.isNotEmpty) {
        isMessageReady = true;
      }
    }
  }

  PocsagMessage? takeMessage() {
    if (!isMessageReady) return null;
    var content = functionBits == 3 ? alphaMsg : numericMsg;
    if (content.isEmpty) {
      content = alphaMsg.isEmpty ? numericMsg : alphaMsg;
    }
    final msg = PocsagMessage(address, functionBits, content);
    isMessageReady = false;
    numericMsg = '';
    alphaMsg = '';
    return msg;
  }
}

class MicDemod {
  MicDemod() : framing = PocsagFraming();

  final PocsagFraming framing;
  final messages = <PocsagMessage>[];

  static const _watchStep = 48000 / 1200;
  static const _preambleWindowLo = 28.0 * 48000 / 44100.0;
  static const _preambleWindowHi = 44.0 * 48000 / 44100.0;

  var _watchCtr = -1.0;
  var _bufferBase = 0;
  var _syncBit = 0;
  var _nSamples = 0;
  var _preambleCount = 0;
  var _pocbit = 0;
  var _atbBit = 0;
  var _atbLen = 0;

  void reset() {
    _watchCtr = -1;
    _bufferBase = 0;
    _syncBit = 0;
    _nSamples = 0;
    _preambleCount = 0;
    _pocbit = 0;
    _atbBit = 0;
    _atbLen = 0;
    framing.resetFraming();
    framing.address = 0;
    framing.numericMsg = '';
    framing.alphaMsg = '';
    framing.isMessageReady = false;
  }

  void processSamples(Int16List samples) {
    final size = samples.length;
    final base = _bufferBase;
    var watchCtr = _watchCtr;
    var syncBit = _syncBit;
    var nSamples = _nSamples;
    var preambleCount = _preambleCount;
    var pocbit = _pocbit;
    var atbBit = _atbBit;
    var atbLen = _atbLen;
    var i = 0;
    while (i < size) {
      final start = i;
      while (i < size) {
        final v = samples[i] >> 8;
        if ((v < -7 && (syncBit == 1 || atbBit == 1)) ||
            (v > 7 && (syncBit == 0 || atbBit == 0))) {
          break;
        }
        i++;
      }
      final runLen = i - start;
      if (runLen > 0) {
        nSamples += runLen;
        atbLen += runLen;
        if (watchCtr != -1) {
          final runEnd = base + i;
          while (watchCtr < runEnd) {
            if (pocbit > 0) {
              framing.feedBit(atbBit == 1);
              pocbit--;
              if (pocbit == 0) {
                framing.resetFraming();
              }
            }
            watchCtr += _watchStep;
          }
        }
      }
      if (i >= size) break;
      final atbCtr = base + i;
      final val = samples[i] >> 8;
      nSamples++;

      var crossing = false;
      if (val < -7 && syncBit == 1) {
        syncBit = 0;
        crossing = true;
      } else if (val > 7 && syncBit == 0) {
        syncBit = 1;
        crossing = true;
      }

      var locked = false;
      if (crossing && pocbit == 0) {
        if (nSamples > _preambleWindowLo && nSamples < _preambleWindowHi) {
          preambleCount++;
          if (preambleCount > 50) {
            preambleCount = 0;
            pocbit = 1250;
            locked = true;
          }
        } else {
          preambleCount = 0;
        }
        nSamples = 0;
      }
      if (!locked) {
        atbLen++;

        if (val < -7 && atbBit == 1) {
          atbBit = 0;
          if (atbLen < _watchStep * 2 &&
              atbLen / _watchStep > 0.32 &&
              atbLen / _watchStep < 1.90) {
            watchCtr = atbCtr + _watchStep / 2;
          }
          atbLen = 0;
        } else if (val > 7 && atbBit == 0) {
          atbBit = 1;
          if (atbLen < _watchStep * 2 &&
              atbLen / _watchStep > 0.32 &&
              atbLen / _watchStep < 1.90) {
            watchCtr = atbCtr + _watchStep / 2;
          }
          atbLen = 0;
        }

        if (watchCtr - atbCtr < 1 && watchCtr != -1) {
          if (pocbit > 0) {
            framing.feedBit(atbBit == 1);
            pocbit--;
            if (pocbit == 0) {
              framing.resetFraming();
            }
          }
          watchCtr += _watchStep;
        }
      }
      i++;
    }
    _watchCtr = watchCtr;
    _syncBit = syncBit;
    _nSamples = nSamples;
    _preambleCount = preambleCount;
    _pocbit = pocbit;
    _atbBit = atbBit;
    _atbLen = atbLen;
    _bufferBase += size;
    final msg = framing.takeMessage();
    if (msg != null) messages.add(msg);
  }
}

class RtlDemod {
  RtlDemod() : framing = PocsagFraming() {
    _lowpassBaud = FirFilter(301, 48000.0, 6000.0);
    _decimationI = FirFilter(151, 240000.0, 20000.0);
    _decimationQ = FirFilter(151, 240000.0, 20000.0);
    _phase.setFMScaling(48000.0 / (2.0 * 4500.0));
  }

  final PocsagFraming framing;
  final messages = <PocsagMessage>[];
  late FirFilter _lowpassBaud;
  late FirFilter _decimationI;
  late FirFilter _decimationQ;
  final _phase = _PhaseDiscriminator();
  final _preambleMA = _MovingAverage2048();

  var magsqRaw = 0.0;
  var _dcOffset = 0.0;
  var _prevData = false;
  var _syncCnt = 0;
  var _hysteresisState = false;
  var _peakPos = 0.01;
  var _peakNeg = -0.01;
  var _decimCounter = 0;
  int? _carry;

  void reset() {
    _lowpassBaud = FirFilter(301, 48000.0, 6000.0);
    _decimationI = FirFilter(151, 240000.0, 20000.0);
    _decimationQ = FirFilter(151, 240000.0, 20000.0);
    _phase._prevArg = 0.0;
    _preambleMA.reset();
    framing.resetFraming();
    framing.address = 0;
    framing.numericMsg = '';
    framing.alphaMsg = '';
    framing.isMessageReady = false;
    magsqRaw = 0.0;
    _dcOffset = 0.0;
    _prevData = false;
    _syncCnt = 0;
    _hysteresisState = false;
    _peakPos = 0.01;
    _peakNeg = -0.01;
    _decimCounter = 0;
    _carry = null;
  }

  static int _clampToInt8(double value) {
    var v = value >= 0 ? (value + 0.5).floor() : (value - 0.5).ceil();
    if (v > 127) v = 127;
    if (v < -128) v = -128;
    return v;
  }

  void pushBytes(Uint8List bytes) {
    final sI = _decimationI._samples;
    final tI = _decimationI._taps;
    final sQ = _decimationQ._samples;
    final tQ = _decimationQ._taps;
    final n = _decimationI._n;
    final pairs = tI.length - 1;
    final sB = _lowpassBaud._samples;
    final tB = _lowpassBaud._taps;
    final nB = _lowpassBaud._n;
    final pairsB = tB.length - 1;
    var pI = _decimationI._ptr;
    var pQ = _decimationQ._ptr;
    var pB = _lowpassBaud._ptr;
    var carry = _carry;
    var decim = _decimCounter;
    var dcOffset = _dcOffset;
    var peakPos = _peakPos;
    var peakNeg = _peakNeg;
    var syncCnt = _syncCnt;
    var prevData = _prevData;
    var hysteresis = _hysteresisState;
    for (var j = 0; j < bytes.length; j++) {
      final c = carry;
      if (c == null) {
        carry = bytes[j];
        continue;
      }
      carry = null;
      final vI = c - 128.0;
      sI[pI] = vI;
      sI[pI + n] = vI;
      final vQ = bytes[j] - 128.0;
      sQ[pQ] = vQ;
      sQ[pQ + n] = vQ;
      if (++decim == 5) {
        decim = 0;
        final loI = pI + 1;
        final hiI = pI + n;
        var accI = 0.0;
        for (var i = 0; i < pairs; i++) {
          accI += (sI[loI + i] + sI[hiI - i]) * tI[i];
        }
        accI += sI[hiI - pairs] * tI[pairs];
        final loQ = pQ + 1;
        final hiQ = pQ + n;
        var accQ = 0.0;
        for (var i = 0; i < pairs; i++) {
          accQ += (sQ[loQ + i] + sQ[hiQ - i]) * tQ[i];
        }
        accQ += sQ[hiQ - pairs] * tQ[pairs];
        final fi = _clampToInt8(accI) / 128.0;
        final fq = _clampToInt8(accQ) / 128.0;
        final (fmDemod, magsq) = _phase.delta(fi, fq);
        magsqRaw = magsq;
        sB[pB] = fmDemod;
        sB[pB + nB] = fmDemod;
        final loB = pB + 1;
        final hiB = pB + nB;
        var filt = 0.0;
        for (var i = 0; i < pairsB; i++) {
          filt += (sB[loB + i] + sB[hiB - i]) * tB[i];
        }
        filt += sB[hiB - pairsB] * tB[pairsB];
        pB = pB == nB - 1 ? 0 : pB + 1;
        if (!framing.gotSC) {
          _preambleMA(filt);
          dcOffset = _preambleMA.asDouble();
        }
        final sampleVal = filt - dcOffset;
        if (sampleVal > peakPos) {
          peakPos = sampleVal;
        } else {
          peakPos *= 0.9999;
        }
        if (sampleVal < peakNeg) {
          peakNeg = sampleVal;
        } else {
          peakNeg *= 0.9999;
        }
        var threshold = (peakPos - peakNeg) * 0.15;
        if (threshold < 0.005) threshold = 0.005;
        if (sampleVal > threshold) {
          hysteresis = true;
        } else if (sampleVal < -threshold) {
          hysteresis = false;
        }
        final data = hysteresis;
        if (data != prevData) {
          syncCnt = 20;
        } else {
          syncCnt--;
          if (syncCnt <= 0) {
            framing.feedBit(data);
            syncCnt = 40;
          }
        }
        prevData = data;
        final msg = framing.takeMessage();
        if (msg != null) messages.add(msg);
      }
      pI = pI == n - 1 ? 0 : pI + 1;
      pQ = pQ == n - 1 ? 0 : pQ + 1;
    }
    _decimationI._ptr = pI;
    _decimationQ._ptr = pQ;
    _lowpassBaud._ptr = pB;
    _carry = carry;
    _decimCounter = decim;
    _dcOffset = dcOffset;
    _peakPos = peakPos;
    _peakNeg = peakNeg;
    _syncCnt = syncCnt;
    _prevData = prevData;
    _hysteresisState = hysteresis;
  }
}

class AudioFft {
  AudioFft(this.fftSize) {
    _input = Float32List(fftSize);
    _window = Float32List(fftSize);
    _real = Float64List(fftSize);
    _imag = Float64List(fftSize);
    _magnitude = Float32List(fftSize);
    var sum = 0.0;
    for (var i = 0; i < fftSize; i++) {
      _window[i] = 0.54 - 0.46 * math.cos(2.0 * math.pi * i / (fftSize - 1));
      sum = _f32(sum + _window[i]);
    }
    final fullScale = _f32(sum * 0.5);
    _dbOffset = 20.0 * (math.log(fullScale) / math.ln10);
    _twiddles = [];
    for (var len = 2; len <= fftSize ~/ 2; len *= 2) {
      final table = Float64List(len);
      for (var k = 0; k < len ~/ 2; k++) {
        final angle = -2.0 * math.pi * k / len;
        table[2 * k] = math.cos(angle);
        table[2 * k + 1] = math.sin(angle);
      }
      _twiddles.add(table);
    }
    _rfftTw = Float64List(fftSize);
    for (var k = 0; k < fftSize ~/ 2; k++) {
      final angle = -2.0 * math.pi * k / fftSize;
      _rfftTw[2 * k] = math.cos(angle);
      _rfftTw[2 * k + 1] = math.sin(angle);
    }
  }

  final int fftSize;
  late final Float32List _input;
  late final Float32List _window;
  late final Float64List _real;
  late final Float64List _imag;
  late final Float32List _magnitude;
  late final List<Float64List> _twiddles;
  late final Float64List _rfftTw;
  var _dbOffset = 0.0;
  var _bufferPos = 0;

  void processSamples(Int16List samples) {
    var src = 0;
    var remaining = samples.length;
    while (remaining > 0) {
      final space = fftSize - _bufferPos;
      final take = remaining < space ? remaining : space;
      final base = _bufferPos;
      for (var k = 0; k < take; k++) {
        _input[base + k] = samples[src + k] / 32768.0;
      }
      _bufferPos += take;
      src += take;
      remaining -= take;
      if (_bufferPos >= fftSize) {
        _computeFft();
        _bufferPos = 0;
      }
    }
  }

  void _computeFft() {
    final n2 = fftSize ~/ 2;
    final re = _real;
    final im = _imag;
    final inp = _input;
    final win = _window;
    for (var n = 0; n < n2; n++) {
      re[n] = inp[2 * n] * win[2 * n];
      im[n] = inp[2 * n + 1] * win[2 * n + 1];
    }
    var j = 0;
    for (var i = 0; i < n2 - 1; i++) {
      if (i < j) {
        var t = re[i];
        re[i] = re[j];
        re[j] = t;
        t = im[i];
        im[i] = im[j];
        im[j] = t;
      }
      var k = n2 ~/ 2;
      while (k <= j) {
        j -= k;
        k ~/= 2;
      }
      j += k;
    }
    var stage = 0;
    for (var len = 2; len <= n2; len *= 2, stage++) {
      final tw = _twiddles[stage];
      final half = len ~/ 2;
      for (var i = 0; i < n2; i += len) {
        for (var k = 0; k < half; k++) {
          final wReal = tw[2 * k];
          final wImag = tw[2 * k + 1];
          final idx1 = i + k;
          final idx2 = idx1 + half;
          final tReal = wReal * re[idx2] - wImag * im[idx2];
          final tImag = wReal * im[idx2] + wImag * re[idx2];
          re[idx2] = re[idx1] - tReal;
          im[idx2] = im[idx1] - tImag;
          re[idx1] = re[idx1] + tReal;
          im[idx1] = im[idx1] + tImag;
        }
      }
    }
    final rtw = _rfftTw;
    final mag = _magnitude;
    for (var k = 0; k < n2; k++) {
      final km = n2 - k;
      final a = re[k];
      final b = im[k];
      final c = re[km == n2 ? 0 : km];
      final d = im[km == n2 ? 0 : km];
      final eRe = (a + c) * 0.5;
      final eIm = (b - d) * 0.5;
      final oRe = (b + d) * 0.5;
      final oIm = (c - a) * 0.5;
      final wRe = rtw[2 * k];
      final wIm = rtw[2 * k + 1];
      final xRe = eRe + (wRe * oRe - wIm * oIm);
      final xIm = eIm + (wRe * oIm + wIm * oRe);
      mag[k] = xRe * xRe + xIm * xIm;
    }
    final xn = re[0] - im[0];
    mag[n2] = xn * xn;
    for (var k = 1; k < n2; k++) {
      mag[fftSize - k] = mag[k];
    }
  }

  Float32List spectrum(int outputSize) {
    final out = Float32List(outputSize);
    final copySize = math.min(outputSize, fftSize ~/ 2);
    for (var i = 0; i < copySize; i++) {
      var power = _magnitude[i];
      if (power < 1e-20) power = 1e-20;
      final dbfs = 10.0 * (math.log(power) / math.ln10) - _dbOffset;
      final normalized = (dbfs + 80.0) / 80.0;
      out[i] = math.max(0.0, math.min(1.0, normalized));
    }
    return out;
  }

  Float32List spectrum500() {
    final spec = spectrum(fftSize ~/ 2);
    final out = Float32List(500);
    final spectrumSize = fftSize ~/ 2;
    for (var i = 0; i < 500; i++) {
      final begin = (i * spectrumSize) ~/ 500;
      final end = ((i + 1) * spectrumSize) ~/ 500;
      var peak = 0.0;
      for (var j = begin; j < end; j++) {
        if (spec[j] > peak) peak = spec[j];
      }
      out[i] = peak;
    }
    return out;
  }
}

import 'dart:math' as math;
import 'dart:typed_data';

import 'ffsk_protocol.dart';

class FfskDecoder {
  final frameLog = <String>[];
  FfskDecoder() {
    final lo = _lowpass(300);
    final hi = _lowpass(4000);
    var sum = 0.0;
    for (var i = 0; i < 257; i++) {
      _taps[i] = hi[i] - lo[i];
      sum += _taps[i];
    }
    _taps[128] -= sum;
  }

  static Float64List _lowpass(double hz) {
    final taps = Float64List(257);
    var sum = 0.0;
    for (var i = 0; i < 257; i++) {
      final x = i - 128;
      final sinc = x != 0
          ? math.sin(2 * math.pi * hz * x / 48000) / (math.pi * x)
          : 2 * hz / 48000;
      taps[i] = sinc * (0.54 - 0.46 * math.cos(2 * math.pi * i / 256));
      sum += taps[i];
    }
    for (var i = 0; i < 257; i++) {
      taps[i] /= sum;
    }
    return taps;
  }

  final _taps = Float64List(257);
  final _history = Float64List(257);
  final _toneHistoryRe = [Float64List(40), Float64List(40)];
  final _toneHistoryIm = [Float64List(40), Float64List(40)];
  final _sumRe = Float64List(2);
  final _sumIm = Float64List(2);
  final finders = List.generate(9, (_) => FfskFrameFinder());
  final _recent = <String, double>{};

  int _head = 0;
  int _toneHead = 0;
  int _samples = 0;
  double _phase = 0;
  double _step = 0.1;
  bool _previous = false;

  int get samples => _samples;
  double get timeSec => _samples / 48000;
  int get syncCount {
    var n = 0;
    for (final f in finders) {
      n += f.syncs;
    }
    return n;
  }

  void reset() {
    _history.fillRange(0, 257, 0);
    for (var t = 0; t < 2; t++) {
      _toneHistoryRe[t].fillRange(0, 40, 0);
      _toneHistoryIm[t].fillRange(0, 40, 0);
      _sumRe[t] = 0;
      _sumIm[t] = 0;
    }
    for (final f in finders) {
      f.reset();
    }
    _recent.clear();
    _head = 0;
    _toneHead = 0;
    _samples = 0;
    _phase = 0;
    _step = 0.1;
    _previous = false;
  }

  List<FfskMessage> feed(Float32List audio) {
    final out = <FfskMessage>[];
    for (var n = 0; n < audio.length; n++, _samples++) {
      final sample = audio[n];
      _history[_head] = sample.isFinite ? sample : 0.0;
      var conditioned = 0.0;
      for (var j = 0; j < 257; j++) {
        conditioned += _taps[j] * _history[(_head + 257 - j) % 257];
      }
      _head = (_head + 1) % 257;
      for (var tone = 0; tone < 2; tone++) {
        final freq = tone == 1 ? 1800.0 : 1200.0;
        final angle = -2 * math.pi * freq * (_samples % 80) / 48000;
        final vre = conditioned * math.cos(angle);
        final vim = conditioned * math.sin(angle);
        _sumRe[tone] += vre - _toneHistoryRe[tone][_toneHead];
        _sumIm[tone] += vim - _toneHistoryIm[tone][_toneHead];
        _toneHistoryRe[tone][_toneHead] = vre;
        _toneHistoryIm[tone][_toneHead] = vim;
      }
      _toneHead = (_toneHead + 1) % 40;
      final e0 = _sumRe[0] * _sumRe[0] + _sumIm[0] * _sumIm[0];
      final e1 = _sumRe[1] * _sumRe[1] + _sumIm[1] * _sumIm[1];
      final bit = e0 > e1;
      final found = <Uint8List>[];
      if (_samples % 5 == 0) {
        final finder = finders[(_samples % 40) ~/ 5];
        finder.feed(bit);
        found.addAll(finder.frames);
        finder.frames.clear();
      }
      if (_samples % 4 == 0) {
        if (bit != _previous) {
          final error = _phase - 0.5;
          _phase -= 0.1 * error;
          _step = (_step - 0.00005 * error).clamp(0.099, 0.101);
        }
        _phase += _step;
        if (_phase >= 1) {
          _phase -= 1;
          final finder = finders[8];
          finder.feed(bit);
          found.addAll(finder.frames);
          finder.frames.clear();
        }
        _previous = bit;
      }
      if (found.isNotEmpty) {
        final now = timeSec;
        for (final frame in found) {
          frameLog.add(
            frame
                .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
                .join(' '),
          );
          final key = String.fromCharCodes(frame);
          final last = _recent[key];
          if (last != null && now - last < 0.15) continue;
          _recent[key] = now;
          final message = parseFfskFrame(frame);
          if (message != null) out.add(message);
        }
      }
      if (_samples % 4800 == 0) {
        final now = timeSec;
        _recent.removeWhere((_, t) => now - t > 1);
      }
    }
    return out;
  }
}

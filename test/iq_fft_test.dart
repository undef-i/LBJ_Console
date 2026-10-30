import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lbjconsole/services/pocsag_demod.dart';

Uint8List toneBytes(double freqHz, {int samples = 4096}) {
  final out = Uint8List(samples * 2);
  for (var n = 0; n < samples; n++) {
    final phase = 2.0 * math.pi * (freqHz / 240000.0) * n;
    out[2 * n] = (127.5 + 127.5 * 0.8 * math.cos(phase)).round();
    out[2 * n + 1] = (127.5 + 127.5 * 0.8 * math.sin(phase)).round();
  }
  return out;
}

int argmax(Float32List values) {
  var best = 0;
  for (var i = 1; i < values.length; i++) {
    if (values[i] > values[best]) best = i;
  }
  return best;
}

void main() {
  test('positive frequency tone peaks right of center', () {
    final fft = IqFft(4096);
    fft.pushBytes(toneBytes(30000));
    final spec = fft.spectrum500();
    expect(argmax(spec), 312);
    expect(spec[312], greaterThan(0.9));
  });

  test('negative frequency tone peaks left of center', () {
    final fft = IqFft(4096);
    fft.pushBytes(toneBytes(-30000));
    final spec = fft.spectrum500();
    expect(argmax(spec), 187);
    expect(spec[187], greaterThan(0.9));
  });

  test('constant bytes are a zero frequency signal at center', () {
    final fft = IqFft(4096);
    fft.pushBytes(Uint8List.fromList(List.filled(8192, 200)));
    final spec = fft.spectrum500();
    expect(argmax(spec), 250);
  });

  test('odd split across pushes keeps samples aligned', () {
    final all = toneBytes(30000);
    final fft = IqFft(4096);
    fft.pushBytes(Uint8List.sublistView(all, 0, 3001));
    fft.pushBytes(Uint8List.sublistView(all, 3001));
    final spec = fft.spectrum500();
    expect(argmax(spec), 312);
  });
}

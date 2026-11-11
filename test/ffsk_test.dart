import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lbjconsole/services/ffsk_protocol.dart';
import 'package:lbjconsole/services/ffsk_demod.dart';

int _syndrome(int word) {
  var w = word;
  for (var i = 15; i >= 0; i--) {
    if (w & (1 << (i + 10)) != 0) w ^= 0x5B9 << i;
  }
  return w;
}

int _encodeWord(int data16) {
  final v = data16 << 10;
  return v | _syndrome(v);
}

Uint8List buildFrame(List<int> address, int functionCode, List<int> payload) {
  final body = <int>[
    0x0C,
    11 + payload.length,
    ...address,
    0x1F,
    0x8C,
    functionCode,
    payload.length,
    ...payload,
  ];
  final crc = crc16Xmodem(Uint8List.fromList(body));
  return Uint8List.fromList([...body, (crc >> 8) & 0xFF, crc & 0xFF]);
}

List<bool> frameBits(Uint8List frame, {bool invert = false}) {
  final bits = <bool>[];
  void push(int value, int n) {
    for (var i = n - 1; i >= 0; i--) {
      bits.add(((value >> i) & 1) == 1);
    }
  }

  push(0x0DD4259F, 32);
  final padded =
      frame.length.isEven ? frame : Uint8List.fromList([...frame, 0]);
  for (var i = 0; i < padded.length; i += 2) {
    push(_encodeWord((padded[i] << 8) | padded[i + 1]), 26);
  }
  return invert ? bits.map((b) => !b).toList() : bits;
}

Float32List modulate(List<bool> bits,
    {int leadBits = 60, bool invertTones = false}) {
  final all = <bool>[];
  for (var i = 0; i < leadBits; i++) {
    all.add(i.isEven);
  }
  all.addAll(bits);
  for (var i = 0; i < 30; i++) {
    all.add(i.isEven);
  }
  final samples = Float32List(4000 + all.length * 40 + 4000);
  var phase = 0.0;
  var at = 4000;
  for (final bit in all) {
    final mark = invertTones ? !bit : bit;
    final freq = mark ? 1200.0 : 1800.0;
    for (var s = 0; s < 40; s++) {
      phase += 2 * math.pi * freq / 48000;
      samples[at++] = 0.4 * math.sin(phase);
    }
  }
  return samples;
}

final klwFrame = buildFrame(
  [0x41, 0x3F, 0x1F, 0x00, 0x00],
  0xA5,
  [0x23, 0x90, 0x04, 0x23, 0x00, 0x94, 0x88, 0x01, 0x23, 0x04, 0x86],
);

final tdcsPayload = [
  0, 0, 1, 0x4B, 0, 0, 0,
  0x0F, 0x02, 0x00,
  0xEF, 0x00,
  0x7B, 0x00,
  0x40, 0xE2, 0x41,
  80, 0, 0,
  0x94, 0x11,
  0x71, 0x02,
  58,
  0xD2, 0x04,
  3, 3,
  0x87, 0xD6, 0x12,
];

final tdcsFrame = buildFrame(
  [0x00, 0x3F, 0x1F, 0x00, 0x00],
  0x30,
  tdcsPayload,
);

void main() {
  loadLocoModelNames('239,HXD3C\n242,HXD3D\n');

  test('frame finder decodes a clean klw frame', () {
    final finder = FfskFrameFinder();
    for (final bit in frameBits(klwFrame)) {
      finder.feed(bit);
    }
    expect(finder.frames.length, 1);
    final msg = parseFfskFrame(finder.frames.single) as FfskKlw;
    expect(msg.locoModel, 'HXD3C');
    expect(msg.locoSerial, '0423');
    expect(msg.tail, '880123');
    expect(msg.command, 0x94);
    expect(msg.pressure, 486);
  });

  test('frame finder corrects two flipped bits in one word', () {
    final bits = frameBits(tdcsFrame);
    bits[40] = !bits[40];
    bits[55] = !bits[55];
    final finder = FfskFrameFinder();
    for (final bit in bits) {
      finder.feed(bit);
    }
    expect(finder.frames.length, 1);
    expect(finder.frames.single, tdcsFrame);
  });

  test('frame finder decodes an inverted bit stream', () {
    final finder = FfskFrameFinder();
    for (final bit in frameBits(klwFrame, invert: true)) {
      finder.feed(bit);
    }
    expect(finder.frames.length, 1);
  });

  test('frame finder rejects a frame with a bad crc', () {
    final broken = Uint8List.fromList(klwFrame);
    broken[15] ^= 0x01;
    final finder = FfskFrameFinder();
    for (final bit in frameBits(broken)) {
      finder.feed(bit);
    }
    expect(finder.frames, isEmpty);
  });

  test('tdcs payload parses into fields', () {
    final msg = parseFfskFrame(tdcsFrame) as FfskTdcs;
    expect(msg.trainPrefix, 'K');
    expect(msg.trainNumber, 527);
    expect(msg.locoModel, 'HXD3C');
    expect(msg.locoSerial, '0123');
    expect(msg.kilometer, closeTo(123.456, 0.0001));
    expect(msg.increasing, isTrue);
    expect(msg.speedKmh, 80);
    expect(msg.weightTonnes, 4500);
    expect(msg.lengthMeters, 62.5);
    expect(msg.carCount, 58);
    expect(msg.stationNo, 1234);
    expect(msg.segmentNo, 3);
    expect(msg.actualSegmentNo, 3);
    expect(msg.driverId, 1234567);
    expect(msg.signalState, 0);
    expect(msg.signalStateName, '始发车');
    expect(msg.signalType, 0);
    expect(msg.trainRole, '客车本务');
  });

  test('ground alarm payload parses into fields', () {
    const timeValue = 56 |
        (34 << 6) |
        (12 << 12) |
        (10 << 17) |
        (11 << 22) |
        (26 << 26);
    final payload = <int>[
      3,
      0x11, 0xB7, 0x33,
      (timeValue >> 24) & 0xFF,
      (timeValue >> 16) & 0xFF,
      (timeValue >> 8) & 0xFF,
      timeValue & 0xFF,
      0,
      ...'TESTLINE'.codeUnits,
    ];
    final frame = buildFrame([0, 0, 0, 0, 0], 0x40, payload);
    final msg = parseFfskFrame(frame) as FfskAlarm;
    expect(msg.function, 3);
    expect(msg.name, '道口事故报警');
    expect(msg.kilometer, closeTo(1161.011, 0.0001));
    expect(msg.sendTime, DateTime(2026, 11, 10, 12, 34, 56));
    expect(msg.lineName, 'TESTLINE');
    expect(msg.detail, '');
  });

  test('ground alarm release carries the reason', () {
    final payload = <int>[
      4,
      0x11, 0xB7, 0x33,
      0, 0, 0, 0,
      1,
      0, 0, 0, 0, 0, 0, 0, 0,
    ];
    final frame = buildFrame([0, 0, 0, 0, 0], 0x40, payload);
    final msg = parseFfskFrame(frame) as FfskAlarm;
    expect(msg.name, '道口事故报警解除');
    expect(msg.detail, '报警解除');
    expect(msg.sendTime, isNull);
  });

  test('train alarm payload parses into fields', () {
    const timeValue = 56 |
        (34 << 6) |
        (12 << 12) |
        (10 << 17) |
        (11 << 22) |
        (26 << 26);
    final payload = <int>[
      1,
      0x4B, 0x20, 0x20, 0x20,
      0x0F, 0x02, 0x00,
      0x12, 0x34, 0x56, 0x78,
      0x11, 0xB7, 0x33,
      (timeValue >> 24) & 0xFF,
      (timeValue >> 16) & 0xFF,
      (timeValue >> 8) & 0xFF,
      timeValue & 0xFF,
      1,
    ];
    final frame = buildFrame([0, 0, 0, 0, 0], 0x40, payload);
    final msg = parseFfskFrame(frame) as FfskAlarm;
    expect(msg.function, 1);
    expect(msg.name, '列车防护报警');
    expect(msg.train, 'K527');
    expect(msg.loco, '12345678');
    expect(msg.kilometer, closeTo(1161.011, 0.0001));
    expect(msg.sendTime, DateTime(2026, 11, 10, 12, 34, 56));
    expect(msg.detail, '控制盒1或MMI1');
  });

  test('tdcs frame with a garbled prefix still parses', () {
    final payload = [...tdcsPayload];
    payload[3] = 0x01;
    final frame = buildFrame([0x00, 0x3F, 0x1F, 0x00, 0x00], 0x30, payload);
    final msg = parseFfskFrame(frame) as FfskTdcs;
    expect(msg.trainPrefix, '');
    expect(msg.trainNumber, 527);
    expect(msg.locoSerial, '0123');
  });

  test('tdcs test sentinel has no kilometer', () {
    final payload = [...tdcsPayload];
    payload[14] = 0x10;
    payload[15] = 0x96;
    payload[16] = 0x98;
    final frame = buildFrame([0x00, 0x3F, 0x1F, 0x00, 0x00], 0x30, payload);
    final msg = parseFfskFrame(frame) as FfskTdcs;
    expect(msg.testFrame, isTrue);
    expect(msg.kilometer, isNull);
    expect(msg.increasing, isFalse);
  });

  test('klw short payload parses loco and pressure', () {
    final frame = buildFrame(
      [0x41, 0x3F, 0x1F, 0x00, 0x00],
      0xA5,
      [0x04, 0x23, 0x00, 0x91, 0x04, 0x86],
    );
    final msg = parseFfskFrame(frame) as FfskKlw;
    expect(msg.locoRaw, '0423');
    expect(msg.locoModel, '');
    expect(msg.tail, '');
    expect(msg.command, 0x91);
    expect(msg.pressure, 486);
  });

  test('klw interleaved payload parses full loco and tail', () {
    final frame = buildFrame(
      [0x41, 0x3F, 0x1F, 0x00, 0x00],
      0xA5,
      [
        0x04, 0x23, 0x00, 0x94, 0x04, 0x86, 0x88,
        0x23, 0x90, 0x01, 0x23, 0, 0, 0, 0,
      ],
    );
    final msg = parseFfskFrame(frame) as FfskKlw;
    expect(msg.locoModel, 'HXD3C');
    expect(msg.locoSerial, '0423');
    expect(msg.tail, '880123');
    expect(msg.command, 0x94);
    expect(msg.pressure, 486);
  });

  test('klw clock payload parses the clock tail', () {
    final frame = buildFrame(
      [0x41, 0x3F, 0x1F, 0x00, 0x00],
      0xA5,
      [
        0x23, 0x90, 0x04, 0x23, 0x00, 0xA1, 0x88, 0x01, 0x23,
        0xFF, 0xFF, 0x25, 0x11, 0x10, 0x17, 0x30, 0x45,
      ],
    );
    final msg = parseFfskFrame(frame) as FfskKlw;
    expect(msg.command, 0xA1);
    expect(msg.tail, '880123');
    expect(msg.param, '');
    expect(msg.clock, '2025-11-10 17:30:45');
  });

  test('klw 450 tail marker drops the tail and shortens the loco', () {
    final frame = buildFrame(
      [0x41, 0x3F, 0x1F, 0x00, 0x00],
      0xA5,
      [
        0x23, 0x90, 0x04, 0x23, 0x00, 0x91, 0xAA, 0xAA, 0xA0,
        0x04, 0x86,
      ],
    );
    final msg = parseFfskFrame(frame) as FfskKlw;
    expect(msg.locoRaw, '2390');
    expect(msg.tail, '');
    expect(msg.command, 0x91);
    expect(msg.pressure, 486);
  });

  test('ffsk audio round trip decodes klw', () {
    final decoder = FfskDecoder();
    final out = decoder.feed(modulate(frameBits(klwFrame)));
    expect(out.length, 1);
    final msg = out.single as FfskKlw;
    expect(msg.tail, '880123');
    expect(msg.pressure, 486);
  });

  test('ffsk audio round trip survives inverted tones', () {
    final decoder = FfskDecoder();
    final out =
        decoder.feed(modulate(frameBits(klwFrame), invertTones: true));
    expect(out.length, 1);
    expect((out.single as FfskKlw).command, 0x94);
  });
}

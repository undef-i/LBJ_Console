import 'dart:math' as math;
import 'dart:typed_data';

import 'ffsk_protocol.dart';

const _syncCode = 0x7CD215D8;
const _idleCode = 0x7A89C197;

int _bchEncode(int cw) {
  var cwE = cw & 0xFFFFF800;
  var localCW = cwE;
  for (var bit = 1; bit <= 21; bit++) {
    if (cwE & 0x80000000 != 0) cwE ^= 0xED200000;
    cwE = (cwE << 1) & 0xFFFFFFFF;
  }
  localCW |= cwE >> 21;
  return localCW;
}

int _codeword(int data21) {
  final cw = _bchEncode(data21 << 11);
  var parity = 0;
  for (var i = 1; i <= 31; i++) {
    parity ^= (cw >> i) & 1;
  }
  return cw | parity;
}

int _reverseN(int v, int n) {
  var r = 0;
  for (var i = 0; i < n; i++) {
    r = (r << 1) | ((v >> i) & 1);
  }
  return r;
}

const _numericChars = [
  '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '.', 'U', ' ', '-',
  ')', '(',
];

List<int> _numericChunks(String content) {
  final chunks = <int>[];
  for (var at = 0; at < content.length; at += 5) {
    var chunk = 0;
    for (var j = 0; j < 5; j++) {
      final idx = at + j < content.length
          ? _numericChars.indexOf(content[at + j])
          : _numericChars.indexOf(' ');
      chunk = (chunk << 4) | _reverseN(idx, 4);
    }
    chunks.add(chunk);
  }
  return chunks;
}

List<int> _alphaChunks(String content) {
  final bits = <int>[];
  for (final c in content.codeUnits) {
    final r = _reverseN(c, 8);
    for (var i = 7; i >= 0; i--) {
      bits.add((r >> i) & 1);
    }
  }
  final chunks = <int>[];
  for (var at = 0; at < bits.length; at += 20) {
    var chunk = 0;
    for (var j = 0; j < 20; j++) {
      chunk = (chunk << 1) | (at + j < bits.length ? bits[at + j] : 0);
    }
    chunks.add(chunk);
  }
  return chunks;
}

Int16List _pocsagTransmission(int address, int function, String content) {
  final chunks = function == 3 ? _alphaChunks(content) : _numericChunks(content);
  final words = <int>[];
  var at = 0;
  var batch = List<int>.filled(17, _idleCode);
  batch[0] = _syncCode;
  final slot = 1 + (address & 7) * 2;
  batch[slot] = _codeword(((address >> 3) << 2) | function);
  var pos = slot + 1;
  while (true) {
    while (pos < 17 && at < chunks.length) {
      batch[pos++] = _codeword((1 << 20) | chunks[at++]);
    }
    words.addAll(batch);
    if (at >= chunks.length) break;
    batch = List<int>.filled(17, _idleCode);
    batch[0] = _syncCode;
    pos = 1;
  }
  final bits = <bool>[];
  for (var i = 0; i < 120; i++) {
    bits.add(i.isEven);
  }
  for (final w in words) {
    for (var i = 31; i >= 0; i--) {
      bits.add(((w >> i) & 1) == 1);
    }
  }
  for (var i = 0; i < 700; i++) {
    bits.add(i.isEven);
  }
  final out = Int16List(bits.length * 40);
  for (var b = 0; b < bits.length; b++) {
    final v = bits[b] ? -16000 : 16000;
    for (var s = 0; s < 40; s++) {
      out[b * 40 + s] = v;
    }
  }
  return out;
}

Int16List lbjSamplePcm({
  required bool up,
  required String sync,
  required String info,
  required String info2,
}) {
  final parts = [
    _pocsagTransmission(1234008, 1, sync),
    _pocsagTransmission(1234000, up ? 3 : 1, info),
    _pocsagTransmission(1234002, 0, info2),
  ];
  final out = Int16List(parts.fold(0, (a, p) => a + p.length));
  var at = 0;
  for (final part in parts) {
    out.setRange(at, at + part.length, part);
    at += part.length;
  }
  return out;
}

String lbjInfo2({
  required String loco,
  required double lat,
  required double lng,
}) {
  const nibbleChars = '0123456789.U -)(';
  String hexNibbles(List<int> bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(nibbleChars[b >> 4]);
      sb.write(nibbleChars[b & 0xF]);
    }
    return sb.toString();
  }

  String minutes(double value) {
    final deg = value.truncate();
    final min = (value - deg) * 60;
    final whole = min.truncate().toString().padLeft(2, '0');
    final frac = ((min - min.truncate()) * 10000)
        .round()
        .toString()
        .padLeft(4, '0');
    return '$whole$frac';
  }

  final sb = StringBuffer()
    ..write(hexNibbles([0x47, 0x00]))
    ..write(loco.padLeft(8, '0'))
    ..write('00')
    ..write(hexNibbles([0xBE, 0xA9, 0xBB, 0xA6, 0xCF, 0xDF, 0x00, 0x00]))
    ..write(lng.truncate().toString().padLeft(3, '0'))
    ..write(minutes(lng))
    ..write(lat.truncate().toString().padLeft(2, '0'))
    ..write(minutes(lat))
    ..write('00000');
  return sb.toString();
}

int _ffskSyndrome(int word) {
  var w = word;
  for (var i = 15; i >= 0; i--) {
    if (w & (1 << (i + 10)) != 0) w ^= 0x5B9 << i;
  }
  return w;
}

Uint8List ffskFrame(List<int> address, int functionCode, List<int> payload) {
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

Int16List ffskSamplePcm(Uint8List frame) {
  final bits = <bool>[];
  void push(int value, int n) {
    for (var i = n - 1; i >= 0; i--) {
      bits.add(((value >> i) & 1) == 1);
    }
  }

  for (var i = 0; i < 60; i++) {
    bits.add(i.isEven);
  }
  push(0x0DD4259F, 32);
  final padded =
      frame.length.isEven ? frame : Uint8List.fromList([...frame, 0]);
  for (var i = 0; i < padded.length; i += 2) {
    final v = (padded[i] << 8) | padded[i + 1];
    push((v << 10) | _ffskSyndrome(v << 10), 26);
  }
  for (var i = 0; i < 30; i++) {
    bits.add(i.isEven);
  }
  final out = Int16List(4000 + bits.length * 40 + 4000);
  var phase = 0.0;
  var at = 4000;
  for (final bit in bits) {
    final freq = bit ? 1200.0 : 1800.0;
    for (var s = 0; s < 40; s++) {
      phase += 2 * math.pi * freq / 48000;
      out[at++] = (0.4 * math.sin(phase) * 32767).round();
    }
  }
  return out;
}

void _le(List<int> p, int at, int value, int n) {
  for (var i = 0; i < n; i++) {
    p[at + i] = (value >> (8 * i)) & 0xFF;
  }
}

List<int> _bcdBytes(String digits) {
  final out = <int>[];
  for (var i = 0; i < digits.length; i += 2) {
    out.add((int.parse(digits[i]) << 4) | int.parse(digits[i + 1]));
  }
  return out;
}

Uint8List tdcsSampleFrame({
  required bool shared,
  required int serial,
  required int speed,
  required int weight,
  required double length,
  required int cars,
  bool test = false,
}) {
  final p = List<int>.filled(32, 0);
  p[0] = 3;
  p[1] = 3;
  p[2] = 1;
  p[3] = shared ? 0x47 : 0x4B;
  _le(p, 7, shared ? 7001 : 527, 3);
  _le(p, 10, shared ? 239 : 240, 2);
  _le(p, 12, shared ? 1 : 123, 2);
  final km = ((serial * 7) % 280) + 3.5;
  _le(p, 14,
      test ? 9999888 : (km * 1000).round() | (serial.isEven ? 0x400000 : 0),
      3);
  _le(p, 17, speed, 3);
  _le(p, 20, weight, 2);
  _le(p, 22, (length * 10).round(), 2);
  p[24] = cars;
  _le(p, 25, 130, 2);
  p[27] = 241;
  p[28] = 1;
  _le(p, 29, 4309870, 3);
  return ffskFrame([0x00, 0x3F, 0x1F, 0x00, 0x00], 0x30, p);
}

Uint8List klwSampleFrame({
  required bool pairA,
  required int command,
  required int? pressure,
  int layout = 11,
  DateTime? now,
}) {
  final locoDigits = pairA ? '23900001' : '24000123';
  final tailDigits = pairA ? '880123' : '880456';
  final paramBytes = pressure == null
      ? _bcdBytes('0000')
      : _bcdBytes(pressure.toString().padLeft(4, '0'));
  final p = Uint8List(layout);
  if (layout == 6) {
    p.setRange(0, 2, _bcdBytes(locoDigits.substring(4)));
    p[3] = command;
    p.setRange(4, 6, paramBytes);
  } else if (layout == 15) {
    final loco = _bcdBytes(locoDigits);
    final tail = _bcdBytes(tailDigits);
    p.setRange(0, 2, loco.sublist(2));
    p[3] = command;
    p.setRange(4, 6, paramBytes);
    p[6] = tail[0];
    p.setRange(7, 9, loco.sublist(0, 2));
    p.setRange(9, 11, tail.sublist(1));
  } else {
    p.setRange(0, 4, _bcdBytes(locoDigits));
    p[5] = command;
    p.setRange(6, 9, _bcdBytes(tailDigits));
    p.setRange(9, 11, paramBytes);
    if (layout == 17 && now != null) {
      p.setRange(
          11,
          17,
          _bcdBytes(
              '${(now.year - 2000).toString().padLeft(2, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}'));
    }
  }
  return ffskFrame([0x41, 0x3F, 0x1F, 0x00, 0x00], 0xA5, p);
}

void _be(List<int> p, int at, int value, int n) {
  for (var i = 0; i < n; i++) {
    p[at + i] = (value >> (8 * (n - 1 - i))) & 0xFF;
  }
}

Uint8List alarmSampleFrame(int kind, DateTime now) {
  final time = (now.second) |
      (now.minute << 6) |
      (now.hour << 12) |
      (now.day << 17) |
      (now.month << 22) |
      ((now.year - 2000) << 26);
  final List<int> p;
  if (kind == 0 || kind == 1) {
    p = List<int>.filled(20, 0);
    p[0] = kind + 1;
    p[1] = 0x47;
    _le(p, 5, 7001, 3);
    p.setRange(8, 12, _bcdBytes('23900001'));
    _be(p, 12, 1161011, 3);
    _be(p, 15, time, 4);
    p[19] = 1;
  } else if (kind >= 2 && kind <= 5) {
    p = List<int>.filled(17, 0);
    p[0] = kind + 1;
    _be(p, 1, 1161011, 3);
    _be(p, 4, time, 4);
    p[8] = kind.isEven ? 0xFF : (kind == 3 ? 1 : 4);
    p.setRange(9, 15, [0xBE, 0xA9, 0xBB, 0xA6, 0xCF, 0xDF]);
  } else {
    p = List<int>.filled(8, 0);
    p[0] = kind + 1;
    p.setRange(1, 5, _bcdBytes('23900001'));
    p[5] = kind == 6 ? 4 : 3;
    p[6] = 1;
    p[7] = 240;
  }
  return ffskFrame([0, 0, 0, 0, 0], 0x40, p);
}

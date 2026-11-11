import 'dart:typed_data';

import 'package:fast_gbk/fast_gbk.dart';

int crc16Xmodem(Uint8List data, [int start = 0, int? end]) {
  var crc = 0;
  final stop = end ?? data.length;
  for (var i = start; i < stop; i++) {
    crc ^= data[i] << 8;
    for (var k = 0; k < 8; k++) {
      crc = (crc & 0x8000) != 0 ? ((crc << 1) ^ 0x1021) : (crc << 1);
      crc &= 0xFFFF;
    }
  }
  return crc;
}

int _popcount(int v) {
  var n = 0;
  var x = v;
  while (x != 0) {
    n += x & 1;
    x >>= 1;
  }
  return n;
}

int _bchSyndrome(int word) {
  var w = word;
  for (var i = 15; i >= 0; i--) {
    if (w & (1 << (i + 10)) != 0) {
      w ^= 0x5B9 << i;
    }
  }
  return w;
}

final List<List<int>> _errorTable = () {
  final t = List.generate(1024, (_) => <int>[]);
  t[0].add(0);
  for (var i = 0; i < 26; i++) {
    final a = 1 << i;
    t[_bchSyndrome(a)].add(a);
    for (var j = 0; j < i; j++) {
      final b = a | (1 << j);
      t[_bchSyndrome(b)].add(b);
    }
  }
  return t;
}();

const _bcdChars = '0123456789?B -][';

String _bcd(Uint8List p, int at, int n) {
  final buffer = StringBuffer();
  for (var i = at; i < at + n; i++) {
    buffer.write(_bcdChars[p[i] >> 4]);
    buffer.write(_bcdChars[p[i] & 15]);
  }
  return buffer.toString();
}

bool _allDigits(String s) {
  if (s.isEmpty) return false;
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c < 0x30 || c > 0x39) return false;
  }
  return true;
}

int _le(Uint8List p, int at, int n) {
  var v = 0;
  for (var i = 0; i < n; i++) {
    v |= p[at + i] << (8 * i);
  }
  return v;
}

int _be(Uint8List p, int at, int n) {
  var v = 0;
  for (var i = 0; i < n; i++) {
    v = (v << 8) | p[at + i];
  }
  return v;
}

const tdcsSignalNames = <int, String>{
  0: '始发车',
  1: '编组站',
  2: '出站',
  3: '进站',
  4: '通过',
  5: '预告',
  6: '容许',
  7: '预留',
  8: '预留',
};

const tdcsRoleNames = <int, String>{
  0: '货车本务',
  1: '客车本务',
  2: '货车补机',
  3: '客车补机',
};

const ffskAlarmNames = <int, String>{
  1: '列车防护报警',
  2: '列车防护报警解除',
  3: '道口事故报警',
  4: '道口事故报警解除',
  5: '施工防护报警',
  6: '施工防护报警解除',
  7: '出入库检测',
  8: '报警试验',
};

const ffskAlarmReasonNames = <int, String>{
  1: '报警解除',
  4: '30s收不到报警消息',
};

const ffskAlarmSourceNames = <int, String>{
  1: '控制盒1或MMI1',
  2: '控制盒2或MMI2',
  3: '主机面板',
};

const ffskAlarmTestPortNames = <int, String>{
  3: '控制盒1或MMI1',
  4: '控制盒2或MMI2',
};

abstract class FfskMessage {
  FfskMessage(this.raw);
  final Uint8List raw;
}

class FfskTdcs extends FfskMessage {
  FfskTdcs(
    super.raw, {
    required this.trainPrefix,
    required this.trainNumber,
    required this.locoCode,
    required this.locoModel,
    required this.locoSerial,
    required this.kilometer,
    required this.increasing,
    required this.testFrame,
    required this.speedKmh,
    required this.weightTonnes,
    required this.lengthMeters,
    required this.carCount,
    required this.stationNo,
    required this.segmentNo,
    required this.actualSegmentNo,
    required this.driverId,
    required this.signalState,
    required this.signalType,
    required this.trainRole,
  });
  final String trainPrefix;
  final int trainNumber;
  final int locoCode;
  final String locoModel;
  final String locoSerial;
  final double? kilometer;
  final bool increasing;
  final bool testFrame;
  final int speedKmh;
  final int weightTonnes;
  final double lengthMeters;
  final int carCount;
  final int stationNo;
  final int segmentNo;
  final int actualSegmentNo;
  final int driverId;
  final int signalState;
  final int signalType;
  final String trainRole;

  String get signalStateName => tdcsSignalNames[signalState] ?? '';
  String get signalTypeName => tdcsSignalNames[signalType] ?? '';
}

class FfskAlarm extends FfskMessage {
  FfskAlarm(
    super.raw, {
    required this.function,
    this.train = '',
    this.loco = '',
    this.kilometer,
    this.sendTime,
    this.detail = '',
    this.lineName = '',
  });
  final int function;
  final String train;
  final String loco;
  final double? kilometer;
  final DateTime? sendTime;
  final String detail;
  final String lineName;

  String get name => ffskAlarmNames[function] ?? '防护报警';
}

class FfskKlw extends FfskMessage {
  FfskKlw(
    super.raw, {
    required this.locoModel,
    required this.locoSerial,
    required this.locoRaw,
    required this.tail,
    required this.command,
    required this.param,
    required this.pressure,
    required this.clock,
  });
  final String locoModel;
  final String locoSerial;
  final String locoRaw;
  final String tail;
  final int command;
  final String param;
  final int? pressure;
  final String? clock;

  String get locoDisplay {
    if (locoModel.isNotEmpty && locoSerial.isNotEmpty) {
      return '$locoModel $locoSerial';
    }
    return locoRaw;
  }
}

FfskMessage? parseFfskFrame(Uint8List f) {
  if (f.length < 13) return null;
  if (f[0] != 0x0C) return null;
  if (f.length != f[1] + 2) return null;
  if (f.length != f[10] + 13) return null;
  if (f[7] != 0x1F || f[8] != 0x8C) return null;
  final crc = (f[f.length - 2] << 8) | f[f.length - 1];
  if (crc16Xmodem(f, 0, f.length - 2) != crc) return null;
  final p = Uint8List.sublistView(f, 11, f.length - 2);
  if (f[2] == 0 &&
      f[3] == 0x3F &&
      f[4] == 0x1F &&
      f[5] == 0 &&
      f[6] == 0 &&
      f[9] == 0x30) {
    if (f[10] != 32) return null;
    return _parseTdcs(f, p);
  }
  if (f[2] == 0x41 &&
      f[3] == 0x3F &&
      f[4] == 0x1F &&
      f[5] == 0 &&
      f[6] <= 1 &&
      f[9] == 0xA5) {
    return _parseKlw(f, p);
  }
  if (f[2] == 0 &&
      f[3] == 0 &&
      f[4] == 0 &&
      f[5] == 0 &&
      f[6] == 0 &&
      f[9] == 0x40) {
    return _parseAlarm(f, p);
  }
  return null;
}

FfskTdcs? _parseTdcs(Uint8List raw, Uint8List p) {
  final prefix = StringBuffer();
  var prefixValid = true;
  for (var i = 3; i < 7; i++) {
    final c = p[i];
    if (c != 0 && c != 0x20) {
      if (c < 32 || c > 126) {
        prefixValid = false;
      } else {
        prefix.writeCharCode(c);
      }
    }
  }
  if (!prefixValid) prefix.clear();
  final trainNumber = _le(p, 7, 3);
  final locoCode = _le(p, 10, 2);
  final driver = _le(p, 29, 3);
  final mileageRaw = _le(p, 14, 3);
  final testFrame = mileageRaw == 9999888 || mileageRaw == 8888888;
  final kmValid =
      !testFrame && mileageRaw != 0xFFFFFF && mileageRaw != 9999999;
  double? km;
  var increasing = false;
  if (kmValid) {
    km = (mileageRaw & 0x3FFFFF) / 1000.0;
    if (mileageRaw & 0x800000 != 0) km = -km;
    increasing = (mileageRaw & 0x400000) != 0;
  }
  return FfskTdcs(
    raw,
    trainPrefix: prefix.toString(),
    trainNumber: trainNumber,
    locoCode: locoCode,
    locoModel: locoModelNames[locoCode] ?? locoCode.toString().padLeft(3, '0'),
    locoSerial: _le(p, 12, 2).toString().padLeft(4, '0'),
    kilometer: km,
    increasing: increasing,
    testFrame: testFrame,
    speedKmh: _le(p, 17, 3) & 0x3FF,
    weightTonnes: _le(p, 20, 2),
    lengthMeters: _le(p, 22, 2) / 10.0,
    carCount: p[24],
    stationNo: _le(p, 25, 2),
    segmentNo: p[27],
    actualSegmentNo: p[28],
    driverId: driver,
    signalState: p[0],
    signalType: p[1],
    trainRole: tdcsRoleNames[p[2] & 3] ?? '',
  );
}

double _alarmKilometer(Uint8List p, int at) {
  final v = _be(p, at, 3);
  final km = (v & 0x3FFFFF) / 1000.0;
  return (v & 0x800000) != 0 ? -km : km;
}

DateTime? _alarmTime(Uint8List p, int at) {
  final v = _be(p, at, 4);
  final second = v & 0x3F;
  final minute = (v >> 6) & 0x3F;
  final hour = (v >> 12) & 0x1F;
  final day = (v >> 17) & 0x1F;
  final month = (v >> 22) & 0xF;
  final year = 2000 + ((v >> 26) & 0x3F);
  if (month < 1 ||
      month > 12 ||
      day < 1 ||
      day > 31 ||
      hour > 23 ||
      minute > 59 ||
      second > 59) {
    return null;
  }
  return DateTime(year, month, day, hour, minute, second);
}

String _alarmLineName(Uint8List p, int at) {
  if (p.length <= at) return '';
  final bytes = p.sublist(at).where((b) => b != 0).toList();
  if (bytes.isEmpty) return '';
  try {
    return gbk.decode(bytes).trim();
  } catch (e) {
    return '';
  }
}

FfskAlarm? _parseAlarm(Uint8List raw, Uint8List p) {
  if (p.isEmpty) return null;
  final function = p[0];
  if (function == 1 || function == 2) {
    if (p.length < 20) return null;
    final prefix = StringBuffer();
    for (var i = 1; i < 5; i++) {
      final c = p[i];
      if (c >= 32 && c <= 126) prefix.writeCharCode(c);
    }
    final loco = _bcd(p, 8, 4);
    return FfskAlarm(
      raw,
      function: function,
      train: '${prefix.toString().trim()}${_le(p, 5, 3)}',
      loco: _allDigits(loco) ? loco : '',
      kilometer: _alarmKilometer(p, 12),
      sendTime: _alarmTime(p, 15),
      detail: ffskAlarmSourceNames[p[19]] ?? '',
    );
  }
  if (function >= 3 && function <= 6) {
    if (p.length < 9) return null;
    var detail = '';
    if ((function == 4 || function == 6) &&
        p[8] != 0xFF &&
        ffskAlarmReasonNames.containsKey(p[8])) {
      detail = ffskAlarmReasonNames[p[8]]!;
    }
    return FfskAlarm(
      raw,
      function: function,
      kilometer: _alarmKilometer(p, 1),
      sendTime: _alarmTime(p, 4),
      detail: detail,
      lineName: _alarmLineName(p, 9),
    );
  }
  if (function == 7 || function == 8) {
    if (p.length < 5) return null;
    final loco = _bcd(p, 1, 4);
    var detail = '';
    if (p.length >= 8) {
      final port = ffskAlarmTestPortNames[p[5]] ?? '';
      detail = [
        if (port.isNotEmpty) port,
        '结果 ${p[6]}',
        '电压 ${(p[7] / 10).toStringAsFixed(1)} V',
      ].join(' ');
    }
    return FfskAlarm(
      raw,
      function: function,
      loco: _allDigits(loco) ? loco : '',
      detail: detail,
    );
  }
  return null;
}

FfskKlw? _parseKlw(Uint8List raw, Uint8List p) {
  final n = p.length;
  Uint8List locoBytes;
  int cmdAt;
  int paramAt;
  var tail = '';
  if (n == 6) {
    locoBytes = Uint8List.sublistView(p, 0, 2);
    cmdAt = 2;
    paramAt = 4;
  } else if (n == 11 || (n == 17 && (p[5] == 0xA1 || p[5] == 0xA2))) {
    locoBytes = Uint8List.sublistView(p, 0, 4);
    cmdAt = 4;
    paramAt = 9;
    if (n == 11 && p[6] == 0xAA && p[7] == 0xAA && p[8] == 0xA0) {
      locoBytes = Uint8List.sublistView(p, 0, 2);
    } else {
      tail = _bcd(p, 6, 3);
    }
  } else if (n == 15) {
    locoBytes = Uint8List.fromList([p[7], p[8], p[0], p[1]]);
    cmdAt = 2;
    paramAt = 4;
    tail = _bcd(Uint8List.fromList([p[6], p[9], p[10]]), 0, 3);
  } else {
    return null;
  }
  final rawLoco = _bcd(locoBytes, 0, locoBytes.length);
  var model = '';
  var serial = '';
  if (rawLoco.length == 8 && _allDigits(rawLoco)) {
    final code = int.parse(rawLoco.substring(0, 3));
    model = locoModelNames[code] ?? rawLoco.substring(0, 3);
    serial = rawLoco.substring(4);
  }
  final command = p[cmdAt + 1];
  final suppressed = p[paramAt] == 0xFF &&
      (p[paramAt + 1] == 0xFF || p[paramAt + 1] == 0xA5);
  final param = suppressed ? '' : _bcd(p, paramAt, 2);
  int? pressure;
  const pressureCommands = {0x91, 0x92, 0x30, 0x31, 0x93, 0x94, 0xA3, 0xA4};
  if (pressureCommands.contains(command) && _allDigits(param)) {
    pressure = int.parse(param);
  }
  String? clock;
  if (n == 17) {
    final digits = _bcd(p, 11, 6);
    if (_allDigits(digits)) {
      final year = 2000 + int.parse(digits.substring(0, 2));
      final month = int.parse(digits.substring(2, 4));
      final day = int.parse(digits.substring(4, 6));
      final hour = int.parse(digits.substring(6, 8));
      final minute = int.parse(digits.substring(8, 10));
      final second = int.parse(digits.substring(10, 12));
      final parsed = DateTime(year, month, day, hour, minute, second);
      if (parsed.year == year &&
          parsed.month == month &&
          parsed.day == day &&
          parsed.hour == hour &&
          parsed.minute == minute &&
          parsed.second == second) {
        clock = '20${digits.substring(0, 2)}-${digits.substring(2, 4)}-'
            '${digits.substring(4, 6)} ${digits.substring(6, 8)}:'
            '${digits.substring(8, 10)}:${digits.substring(10, 12)}';
      }
    }
  }
  return FfskKlw(
    raw,
    locoModel: model,
    locoSerial: serial,
    locoRaw: rawLoco,
    tail: tail,
    command: command,
    param: param,
    pressure: pressure,
    clock: clock,
  );
}

class _FfskCandidate {
  _FfskCandidate(this.bytes, this.corrected);
  final Uint8List bytes;
  final int corrected;
}

class FfskFrameFinder {
  int syncs = 0;
  int crcFailures = 0;
  int rejected = 0;
  int ambiguous = 0;
  final List<Uint8List> frames = [];

  int _shift = 0;
  int _seen = 0;
  bool _active = false;
  bool _inverted = false;
  int _word = 0;
  int _bits = 0;
  List<_FfskCandidate> _candidates = [];

  void reset() {
    _shift = 0;
    _seen = 0;
    _active = false;
    _inverted = false;
    _word = 0;
    _bits = 0;
    _candidates = [];
    frames.clear();
  }

  void feed(bool bit) {
    _shift = ((_shift << 1) | (bit ? 1 : 0)) & 0xFFFFFFFF;
    if (_seen < 32) _seen++;
    if (!_active) {
      if (_seen < 32) return;
      final e = _popcount(_shift ^ 0x0DD4259F);
      if (e > 2 && e < 30) return;
      _active = true;
      _inverted = e >= 30;
      _word = 0;
      _bits = 0;
      _candidates = [_FfskCandidate(Uint8List(0), 0)];
      syncs++;
      return;
    }
    _word = ((_word << 1) | ((bit ^ _inverted) ? 1 : 0)) & 0x3FFFFFF;
    if (++_bits < 26) return;
    final pending = <String, _FfskCandidate>{};
    final valid = <String, (Uint8List, int)>{};
    for (final prev in _candidates) {
      for (final mask in _errorTable[_bchSyndrome(_word)]) {
        final value = ((_word ^ mask) >> 10) & 0xFFFF;
        final data = Uint8List(prev.bytes.length + 2);
        data.setAll(0, prev.bytes);
        data[prev.bytes.length] = (value >> 8) & 0xFF;
        data[prev.bytes.length + 1] = value & 0xFF;
        final expected = data[1] + 2;
        if (data[0] != 0x0C || expected < 13 || expected > 257) continue;
        if (data.length >= 12 &&
            (data[1] != data[10] + 11 ||
                data[7] != 0x1F ||
                data[8] != 0x8C)) {
          continue;
        }
        final corrected = prev.corrected + _popcount(mask);
        if (data.length < expected) {
          final key = String.fromCharCodes(data);
          final old = pending[key];
          if (old == null || corrected < old.corrected) {
            pending[key] = _FfskCandidate(data, corrected);
          }
        } else {
          final frame = Uint8List.fromList(data.sublist(0, expected));
          if (parseFfskFrame(frame) != null) {
            final key = String.fromCharCodes(frame);
            final old = valid[key];
            if (old == null || corrected < old.$2) {
              valid[key] = (frame, corrected);
            }
          } else {
            crcFailures++;
          }
        }
      }
    }
    _word = 0;
    _bits = 0;
    if (valid.isNotEmpty) {
      if (valid.length == 1) {
        frames.add(valid.values.first.$1);
      } else {
        ambiguous++;
      }
      _active = false;
      _candidates = [];
    } else if (pending.isEmpty || pending.length > 64) {
      rejected++;
      _active = false;
      _candidates = [];
    } else {
      _candidates = pending.values.toList();
    }
  }
}
final locoModelNames = <int, String>{};
final _locoModelCodes = <String, int>{};

int? locoModelCode(String name) => _locoModelCodes[name.trim()];

void loadLocoModelNames(String text) {
  locoModelNames.clear();
  _locoModelCodes.clear();
  for (final line in text.split('\n')) {
    final comma = line.indexOf(',');
    if (comma <= 0) continue;
    final code = int.tryParse(line.substring(0, comma).trim());
    final name = line.substring(comma + 1).trim();
    if (code != null && name.isNotEmpty) {
      locoModelNames[code] = name;
      _locoModelCodes[name] = code;
    }
  }
}

String resolveLocoModel(String stored) {
  final code = int.tryParse(stored.trim());
  if (code != null) {
    final name = locoModelNames[code];
    if (name != null) return name;
  }
  return stored;
}

String locoDigitsDisplay(String raw) {
  final digits = raw.trim();
  if (digits.length == 8 && digits[3] == '0') {
    final model = locoModelNames[int.tryParse(digits.substring(0, 3)) ?? -1];
    if (model != null) return '$model-${digits.substring(3)}';
  }
  return raw;
}

Map<String, dynamic> klwEventJson(FfskKlw m, String uniqueId, int nowMs) {
  return {
    'uniqueId': uniqueId,
    'timestamp': nowMs,
    'receivedTimestamp': nowMs,
    'rawLocoNumber': m.locoRaw,
    'tailNumber': m.tail,
    'commandCode': m.command,
    'parameter': m.clock ?? m.param,
    'pressureKpa': m.pressure,
  };
}

Map<String, dynamic> tdcsRecordJson(
  FfskTdcs m,
  String uniqueId,
  int nowMs,
  double rssi,
) {
  return {
    'uniqueId': uniqueId,
    'receivedTimestamp': nowMs,
    'timestamp': nowMs,
    'rssi': rssi,
    'trainNumber': '${m.trainPrefix}${m.trainNumber}',
    'rawLocoNumber': '${m.locoCode.toString().padLeft(3, '0')}0${m.locoSerial}',
    'speedKmh': m.speedKmh.toString(),
    'kilometerMark': m.kilometer != null ? m.kilometer!.toStringAsFixed(3) : '',
    'directionCode': m.kilometer != null ? (m.increasing ? 2 : 4) : 0,
    'source': 'tdcs',
    'stationNumber': m.stationNo.toString(),
    'segmentNumber': m.segmentNo.toString(),
    'actualSegmentNumber': m.actualSegmentNo.toString(),
    'driverNumber': m.driverId.toString(),
    'signalState': m.signalStateName,
    'signalType': m.signalTypeName,
    'trainRole': m.trainRole,
    'weightTonnes': m.weightTonnes.toString(),
    'lengthMeters': m.lengthMeters.toStringAsFixed(1),
    'carCount': m.carCount.toString(),
  };
}

Map<String, dynamic> alarmEventJson(FfskAlarm m, String uniqueId, int nowMs) {
  return {
    'uniqueId': uniqueId,
    'timestamp': nowMs,
    'receivedTimestamp': nowMs,
    'functionCode': m.function,
    'trainNumber': m.train,
    'rawLocoNumber': m.loco,
    'kilometer': m.kilometer,
    'detail': m.detail,
    'lineName': m.lineName,
  };
}

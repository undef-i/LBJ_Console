import 'dart:math';
import 'dart:typed_data';

class _Reader {
  final Uint8List buf;
  var pos = 0;

  _Reader(this.buf);

  bool get done => pos >= buf.length;

  int varint() {
    var result = 0;
    var shift = 0;
    while (true) {
      final b = buf[pos++];
      result |= (b & 0x7f) << shift;
      if (b & 0x80 == 0) return result;
      shift += 7;
    }
  }

  void skipValue(int wire) {
    switch (wire) {
      case 0:
        varint();
      case 1:
        pos += 8;
      case 2:
        pos += varint();
      case 5:
        pos += 4;
      default:
        throw const FormatException('unsupported wire type');
    }
  }
}

class _Field {
  final int number;
  final int wire;
  final int start;
  final int end;
  final int varintValue;
  final Uint8List? bytesValue;

  const _Field(this.number, this.wire, this.start, this.end, this.varintValue,
      this.bytesValue);
}

List<_Field> _fields(Uint8List buf) {
  final reader = _Reader(buf);
  final fields = <_Field>[];
  while (!reader.done) {
    final start = reader.pos;
    final key = reader.varint();
    final number = key >> 3;
    final wire = key & 0x7;
    var varintValue = 0;
    Uint8List? bytesValue;
    if (wire == 0) {
      varintValue = reader.varint();
    } else if (wire == 2) {
      final length = reader.varint();
      bytesValue = Uint8List.sublistView(buf, reader.pos, reader.pos + length);
      reader.pos += length;
    } else {
      reader.skipValue(wire);
    }
    fields.add(
        _Field(number, wire, start, reader.pos, varintValue, bytesValue));
  }
  return fields;
}

class _Writer {
  final _buf = <int>[];

  void varint(int value) {
    var v = value;
    while (true) {
      final b = v & 0x7f;
      v >>= 7;
      if (v == 0) {
        _buf.add(b);
        return;
      }
      _buf.add(b | 0x80);
    }
  }

  void raw(Uint8List data) => _buf.addAll(data);

  void lengthDelimited(int field, List<int> data) {
    varint((field << 3) | 2);
    varint(data.length);
    _buf.addAll(data);
  }

  void packedVarints(int field, List<int> values) {
    final inner = _Writer();
    for (final value in values) {
      inner.varint(value);
    }
    lengthDelimited(field, inner._buf);
  }

  Uint8List finish() => Uint8List.fromList(_buf);
}

int _zigzagDecode(int value) => (value >> 1) ^ -(value & 1);

int _zigzagEncode(int value) => (value << 1) ^ (value >> 63);

class _Pt {
  final int x;
  final int y;

  const _Pt(this.x, this.y);
}

class _Path {
  final points = <_Pt>[];
  var closed = false;
}

List<_Path> _decodeGeometry(List<int> geometry) {
  final paths = <_Path>[];
  _Path? current;
  var x = 0;
  var y = 0;
  var i = 0;
  while (i < geometry.length) {
    final command = geometry[i++];
    final type = command & 0x7;
    final count = command >> 3;
    if (type == 7) {
      if (current != null) current.closed = true;
      continue;
    }
    for (var n = 0; n < count; n++) {
      x += _zigzagDecode(geometry[i++]);
      y += _zigzagDecode(geometry[i++]);
      if (type == 1 && n == 0) {
        current = _Path();
        paths.add(current);
      }
      current!.points.add(_Pt(x, y));
    }
  }
  return paths;
}

List<int> _encodeGeometry(List<_Path> paths) {
  final out = <int>[];
  var x = 0;
  var y = 0;
  void delta(_Pt p) {
    out.add(_zigzagEncode(p.x - x));
    out.add(_zigzagEncode(p.y - y));
    x = p.x;
    y = p.y;
  }

  for (final path in paths) {
    if (path.points.isEmpty) continue;
    out.add((1 << 3) | 1);
    delta(path.points.first);
    if (path.points.length > 1) {
      out.add(((path.points.length - 1) << 3) | 2);
      for (var i = 1; i < path.points.length; i++) {
        delta(path.points[i]);
      }
    }
    if (path.closed) out.add(15);
  }
  return out;
}

double _pointSegmentDistance(_Pt p, _Pt a, _Pt b) {
  final dx = b.x - a.x;
  final dy = b.y - a.y;
  final lengthSq = dx * dx + dy * dy;
  if (lengthSq == 0) {
    final ex = p.x - a.x;
    final ey = p.y - a.y;
    return sqrt(ex * ex + ey * ey);
  }
  var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSq;
  t = max(0.0, min(1.0, t));
  final ex = p.x - (a.x + t * dx);
  final ey = p.y - (a.y + t * dy);
  return sqrt(ex * ex + ey * ey);
}

List<_Pt> _simplifyLine(List<_Pt> points, double tolerance) {
  if (points.length <= 2) return points;
  final keep = List<bool>.filled(points.length, false);
  keep[0] = true;
  keep[points.length - 1] = true;
  final stack = <(int, int)>[(0, points.length - 1)];
  while (stack.isNotEmpty) {
    final (a, b) = stack.removeLast();
    var maxDistance = 0.0;
    var index = -1;
    for (var i = a + 1; i < b; i++) {
      final distance = _pointSegmentDistance(points[i], points[a], points[b]);
      if (distance > maxDistance) {
        maxDistance = distance;
        index = i;
      }
    }
    if (index >= 0 && maxDistance > tolerance) {
      keep[index] = true;
      stack.add((a, index));
      stack.add((index, b));
    }
  }
  return [
    for (var i = 0; i < points.length; i++)
      if (keep[i]) points[i]
  ];
}

List<_Pt> _simplifyRing(List<_Pt> points, double tolerance) {
  if (points.length < 3) return points;
  final result = _simplifyLine([...points, points.first], tolerance);
  final ring = result.sublist(0, result.length - 1);
  if (ring.length < 3) return points;
  return ring;
}

List<int> _packedVarintValues(Uint8List data) {
  final reader = _Reader(data);
  final values = <int>[];
  while (!reader.done) {
    values.add(reader.varint());
  }
  return values;
}

Uint8List _simplifyFeature(Uint8List data, double tolerance) {
  final fields = _fields(data);
  var type = 0;
  for (final field in fields) {
    if (field.number == 3 && field.wire == 0) type = field.varintValue;
  }
  if (type != 2 && type != 3) return data;
  final writer = _Writer();
  for (final field in fields) {
    if (field.number == 4 && field.wire == 2) {
      final geometry = _packedVarintValues(field.bytesValue!);
      final paths = _decodeGeometry(geometry);
      final simplified = [
        for (final path in paths)
          _Path()
            ..points.addAll(type == 3 && path.closed
                ? _simplifyRing(path.points, tolerance)
                : _simplifyLine(path.points, tolerance))
            ..closed = path.closed
      ];
      writer.packedVarints(4, _encodeGeometry(simplified));
    } else {
      writer.raw(Uint8List.sublistView(data, field.start, field.end));
    }
  }
  return writer.finish();
}

Uint8List _simplifyLayer(Uint8List data) {
  final fields = _fields(data);
  var extent = 4096;
  for (final field in fields) {
    if (field.number == 5 && field.wire == 0) extent = field.varintValue;
  }
  final tolerance = extent / 512;
  final writer = _Writer();
  for (final field in fields) {
    if (field.number == 2 && field.wire == 2) {
      writer.lengthDelimited(2, _simplifyFeature(field.bytesValue!, tolerance));
    } else {
      writer.raw(Uint8List.sublistView(data, field.start, field.end));
    }
  }
  return writer.finish();
}

Uint8List simplifyVectorTile(Uint8List data) {
  final writer = _Writer();
  for (final field in _fields(data)) {
    if (field.number == 3 && field.wire == 2) {
      writer.lengthDelimited(3, _simplifyLayer(field.bytesValue!));
    } else {
      writer.raw(Uint8List.sublistView(data, field.start, field.end));
    }
  }
  return writer.finish();
}

String _layerName(Uint8List data) {
  for (final field in _fields(data)) {
    if (field.number == 1 && field.wire == 2) {
      return String.fromCharCodes(field.bytesValue!);
    }
  }
  return '';
}

Uint8List stripVectorTileLayers(Uint8List data, Set<String> keep) {
  final writer = _Writer();
  for (final field in _fields(data)) {
    if (field.number == 3 &&
        field.wire == 2 &&
        !keep.contains(_layerName(field.bytesValue!))) {
      continue;
    }
    writer.raw(Uint8List.sublistView(data, field.start, field.end));
  }
  return writer.finish();
}

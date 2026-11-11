import 'dart:convert';
import 'package:lbjconsole/services/ffsk_protocol.dart';
import 'package:lbjconsole/util/train_type_util.dart';
import 'package:lbjconsole/util/loco_info_util.dart';

(double, double)? _gpsFromPair(String text) {
  final parts = text.split(',');
  if (parts.length != 2) return null;
  final lat = double.tryParse(parts[0].trim());
  final lng = double.tryParse(parts[1].trim());
  if (lat == null || lng == null) return null;
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
  if (lat.abs() <= 0.001 && lng.abs() <= 0.001) return null;
  return (lat, lng);
}

(double, double)? _gpsFromDms(String text) {
  final parts = text.trim().split(RegExp(r'\s+'));
  if (parts.length < 2) return null;
  double? dms(String part) {
    final degreeIndex = part.indexOf('°');
    if (degreeIndex == -1) return null;
    final degrees = double.tryParse(part.substring(0, degreeIndex));
    if (degrees == null) return null;
    final minuteIndex = part.indexOf('′');
    if (minuteIndex == -1) return degrees;
    final minutes =
        double.tryParse(part.substring(degreeIndex + 1, minuteIndex));
    if (minutes == null) return degrees;
    return degrees + minutes / 60.0;
  }

  final lat = dms(parts[0]);
  final lng = dms(parts[1]);
  if (lat == null || lng == null) return null;
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
  if (lat.abs() <= 0.001 && lng.abs() <= 0.001) return null;
  return (lat, lng);
}

class TrainRecord {
  final String uniqueId;
  final DateTime timestamp;
  final DateTime receivedTimestamp;
  final String trainNumber;
  final int directionCode;
  final String speedKmh;
  final String kilometerMark;
  final String rawLocoNumber;
  final String parsedLocoNumber;
  final String route;
  final double? latitude;
  final double? longitude;
  final double rssi;
  final String source;
  final String weightTonnes;
  final String lengthMeters;
  final String carCount;
  final String stationNumber;
  final String segmentNumber;
  final String actualSegmentNumber;
  final String driverNumber;
  final String signalState;
  final String signalType;
  final String trainRole;

  TrainRecord({
    required this.uniqueId,
    required this.timestamp,
    required this.receivedTimestamp,
    required this.trainNumber,
    required this.directionCode,
    required this.speedKmh,
    required this.kilometerMark,
    required this.rawLocoNumber,
    required this.parsedLocoNumber,
    required this.route,
    this.latitude,
    this.longitude,
    required this.rssi,
    this.source = 'lbj',
    this.weightTonnes = '',
    this.lengthMeters = '',
    this.carCount = '',
    this.stationNumber = '',
    this.segmentNumber = '',
    this.actualSegmentNumber = '',
    this.driverNumber = '',
    this.signalState = '',
    this.signalType = '',
    this.trainRole = '',
  });

  factory TrainRecord.fromJson(Map<String, dynamic> json) {
    String s(Object? v) => v?.toString() ?? '';

    var trainNumber = s(json['trainNumber']);
    if (trainNumber.isEmpty) {
      final digits = s(json['train']);
      final cls = s(json['lbjClass'] ?? json['lbj_class']).trim();
      trainNumber = (cls.isEmpty || cls == 'NA' || digits.startsWith(cls))
          ? digits
          : '$cls$digits';
    }

    var rawLocoNumber = s(json['rawLocoNumber']);
    var parsedLocoNumber = s(json['parsedLocoNumber']);
    if (rawLocoNumber.isEmpty && parsedLocoNumber.isEmpty) {
      final loco = s(json['loco']).trim();
      final type = s(json['locoType'] ?? json['loco_type']).trim();
      final digitsOnly = RegExp(r'^\d+$').hasMatch(loco);
      final code = int.tryParse(type);
      if (loco.length == 8 && digitsOnly) {
        rawLocoNumber = loco;
      } else if (code != null && loco.length == 4 && digitsOnly) {
        rawLocoNumber = '${code.toString().padLeft(3, '0')}0$loco';
      } else if (loco.isNotEmpty && !digitsOnly) {
        parsedLocoNumber = loco;
      } else if (type.isNotEmpty && loco.isNotEmpty) {
        parsedLocoNumber = '$type-$loco';
      } else if (type.isNotEmpty) {
        parsedLocoNumber = type;
      } else {
        parsedLocoNumber = loco;
      }
    }

    double? latitude = (json['latitude'] as num?)?.toDouble();
    double? longitude = (json['longitude'] as num?)?.toDouble();
    final positionRaw = s(json['position'] ?? json['pos']);
    final pair = _gpsFromPair(positionRaw);
    var kilometerMark = s(json['kilometerMark']);
    if (latitude == null || longitude == null) {
      final gps = pair ??
          _gpsFromDms(
              s(json['positionInfo'] ?? json['position_info'] ?? json['gpsPosition']));
      if (gps != null) {
        latitude = gps.$1;
        longitude = gps.$2;
      }
    }
    if (kilometerMark.isEmpty && pair == null) {
      kilometerMark = positionRaw;
    }

    return TrainRecord(
      uniqueId: s(json['uniqueId'] ?? json['unique_id']),
      timestamp:
          DateTime.fromMillisecondsSinceEpoch((json['timestamp'] as num?)?.toInt() ?? 0),
      receivedTimestamp: DateTime.fromMillisecondsSinceEpoch(
          (json['receivedTimestamp'] ?? json['received_timestamp'] as num?)?.toInt() ?? 0),
      trainNumber: trainNumber,
      directionCode: (json['directionCode'] ?? json['direction'] ?? json['dir'] as num?)?.toInt() ?? 0,
      speedKmh: s(json['speedKmh'] ?? json['speed']),
      kilometerMark: kilometerMark,
      rawLocoNumber: rawLocoNumber,
      parsedLocoNumber: parsedLocoNumber,
      route: s(json['route']),
      latitude: latitude,
      longitude: longitude,
      rssi: (json['rssi'] as num?)?.toDouble() ?? 0.0,
      source: json['source']?.toString() ?? 'lbj',
      weightTonnes: s(json['weightTonnes'] ?? json['weight']),
      lengthMeters: s(json['lengthMeters'] ?? json['length']),
      carCount: s(json['carCount'] ?? json['cars']),
      stationNumber: s(json['stationNumber'] ?? json['station']),
      segmentNumber: s(json['segmentNumber'] ?? json['segment']),
      actualSegmentNumber:
          s(json['actualSegmentNumber'] ?? json['actualSegment']),
      driverNumber: s(json['driverNumber'] ?? json['driver']),
      signalState: s(json['signalState']),
      signalType: s(json['signalType']),
      trainRole: s(json['trainRole']),
    );
  }

  factory TrainRecord.fromJsonString(String jsonString) {
    final json = jsonDecode(jsonString);
    return TrainRecord.fromJson(json);
  }

  factory TrainRecord.fromDatabaseJson(Map<String, dynamic> json) =>
      TrainRecord.fromJson(json);

  Map<String, dynamic> toJson() {
    return {
      'uniqueId': uniqueId,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'receivedTimestamp': receivedTimestamp.millisecondsSinceEpoch,
      'trainNumber': trainNumber,
      'directionCode': directionCode,
      'speedKmh': speedKmh,
      'kilometerMark': kilometerMark,
      'rawLocoNumber': rawLocoNumber,
      'parsedLocoNumber': parsedLocoNumber,
      'route': route,
      'latitude': latitude,
      'longitude': longitude,
      'rssi': rssi,
      'source': source,
      'weightTonnes': weightTonnes,
      'lengthMeters': lengthMeters,
      'carCount': carCount,
      'stationNumber': stationNumber,
      'segmentNumber': segmentNumber,
      'actualSegmentNumber': actualSegmentNumber,
      'driverNumber': driverNumber,
      'signalState': signalState,
      'signalType': signalType,
      'trainRole': trainRole,
    };
  }

  Map<String, dynamic> toDatabaseJson() => toJson();

  String get formattedLocoInfo {
    if (rawLocoNumber.isNotEmpty) return locoDigitsDisplay(rawLocoNumber);
    return parsedLocoNumber;
  }

  String get locoModelName {
    if (rawLocoNumber.length >= 3) {
      final code = int.tryParse(rawLocoNumber.substring(0, 3));
      return code != null ? locoModelNames[code] ?? '' : '';
    }
    final parsed = parsedLocoNumber.trim();
    final dash = parsed.lastIndexOf('-');
    return dash > 0 ? parsed.substring(0, dash) : parsed;
  }

  String get directionChar {
    if (directionCode == 1) return '下';
    if (directionCode == 3) return '上';
    return '';
  }

  bool get hasValidRoute {
    final value = route.trim();
    return value.isNotEmpty &&
        !value.runes.every((r) => r == '*'.runes.first);
  }

  bool get hasValidPosition {
    final value = kilometerMark.trim();
    return value.isNotEmpty &&
        !value.runes
            .every((r) => r == '-'.runes.first || r == '.'.runes.first) &&
        value != '<NUL>';
  }

  bool get hasValidSpeed {
    final value = speedKmh.trim();
    return value.isNotEmpty &&
        !value.runes
            .every((r) => r == '*'.runes.first || r == '-'.runes.first) &&
        value != 'NUL' &&
        value != '<NUL>';
  }

  bool get hasGps => latitude != null && longitude != null;

  String get speedText {
    return '${speedKmh.trim().replaceAll(' ', '')} km/h';
  }

  String get positionText {
    final value = kilometerMark.trim();
    final base =
        '${value.endsWith('.') ? value.substring(0, value.length - 1) : value}K';
    var text = base;
    if (directionCode == 2) text = '$base(+)';
    if (directionCode == 4) text = '$base(-)';
    if (signalState.trim().isNotEmpty) text = '$text ${signalState.trim()}';
    return text;
  }

  String get displayTime {
    return receivedTimestamp.toString().split('.')[0];
  }

  String get extrasRole => trainRole.trim();

  String get extrasPlace {
    final seg = segmentNumber.trim();
    final actual = actualSegmentNumber.trim();
    return [
      if (stationNumber.trim().isNotEmpty) '站 ${stationNumber.trim()}',
      if (seg.isNotEmpty) '段 $seg${actual.isNotEmpty ? ' / $actual' : ''}',
      if (seg.isEmpty && actual.isNotEmpty) '/ $actual',
    ].join(' ');
  }

  String get extrasDriver =>
      driverNumber.trim().isNotEmpty ? '司机 ${driverNumber.trim()}' : '';

  String get extrasStats {
    return [
      if (weightTonnes.trim().isNotEmpty) '${weightTonnes.trim()} 吨',
      if (lengthMeters.trim().isNotEmpty) '${lengthMeters.trim()} 米',
      if (carCount.trim().isNotEmpty) '${carCount.trim()} 辆',
    ].join(' / ');
  }

  String get extrasLine {
    return [
      [extrasRole, extrasStats].where((s) => s.isNotEmpty).join(' '),
      [extrasPlace, extrasDriver].where((s) => s.isNotEmpty).join(' '),
    ].where((s) => s.isNotEmpty).join('\n');
  }

  String get trainType {
    return TrainTypeUtil.getTrainType(trainNumber, at: receivedTimestamp) ??
        '未知';
  }

  String? get locoInfo {
    return LocoInfoUtil.getLocoInfoDisplay(locoModelName, trainNumber);
  }

  Map<String, double> getCoordinates() {
    return {'lat': latitude ?? 0.0, 'lng': longitude ?? 0.0};
  }

  TrainRecord copyWith({
    String? uniqueId,
    DateTime? timestamp,
    DateTime? receivedTimestamp,
    String? trainNumber,
    int? directionCode,
    String? speedKmh,
    String? kilometerMark,
    String? rawLocoNumber,
    String? parsedLocoNumber,
    String? route,
    double? latitude,
    double? longitude,
    double? rssi,
    String? source,
    String? weightTonnes,
    String? lengthMeters,
    String? carCount,
    String? stationNumber,
    String? segmentNumber,
    String? actualSegmentNumber,
    String? driverNumber,
    String? signalState,
    String? signalType,
    String? trainRole,
  }) {
    return TrainRecord(
      uniqueId: uniqueId ?? this.uniqueId,
      timestamp: timestamp ?? this.timestamp,
      receivedTimestamp: receivedTimestamp ?? this.receivedTimestamp,
      trainNumber: trainNumber ?? this.trainNumber,
      directionCode: directionCode ?? this.directionCode,
      speedKmh: speedKmh ?? this.speedKmh,
      kilometerMark: kilometerMark ?? this.kilometerMark,
      rawLocoNumber: rawLocoNumber ?? this.rawLocoNumber,
      parsedLocoNumber: parsedLocoNumber ?? this.parsedLocoNumber,
      route: route ?? this.route,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      rssi: rssi ?? this.rssi,
      source: source ?? this.source,
      weightTonnes: weightTonnes ?? this.weightTonnes,
      lengthMeters: lengthMeters ?? this.lengthMeters,
      carCount: carCount ?? this.carCount,
      stationNumber: stationNumber ?? this.stationNumber,
      segmentNumber: segmentNumber ?? this.segmentNumber,
      actualSegmentNumber: actualSegmentNumber ?? this.actualSegmentNumber,
      driverNumber: driverNumber ?? this.driverNumber,
      signalState: signalState ?? this.signalState,
      signalType: signalType ?? this.signalType,
      trainRole: trainRole ?? this.trainRole,
    );
  }

  @override
  String toString() {
    return 'TrainRecord(uniqueId: $uniqueId, trainNumber: $trainNumber, directionCode: $directionCode, speedKmh: $speedKmh, kilometerMark: $kilometerMark)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TrainRecord && other.uniqueId == uniqueId;
  }

  @override
  int get hashCode => uniqueId.hashCode;
}

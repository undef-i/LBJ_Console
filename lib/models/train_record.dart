import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:lbjconsole/util/train_type_util.dart';
import 'package:lbjconsole/util/loco_info_util.dart';

class TrainRecord {
  final String uniqueId;
  final DateTime timestamp;
  final DateTime receivedTimestamp;
  final String train;
  final int direction;
  final String speed;
  final String position;
  final String time;
  final String loco;
  final String locoType;
  final String lbjClass;
  final String route;
  final String positionInfo;
  final double rssi;

  TrainRecord({
    required this.uniqueId,
    required this.timestamp,
    required this.receivedTimestamp,
    required this.train,
    required this.direction,
    required this.speed,
    required this.position,
    required this.time,
    required this.loco,
    required this.locoType,
    required this.lbjClass,
    required this.route,
    required this.positionInfo,
    required this.rssi,
  });

  factory TrainRecord.fromJson(Map<String, dynamic> json) {
    return TrainRecord(
      uniqueId: json['uniqueId'] ?? json['unique_id'] ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] ?? 0),
      receivedTimestamp: DateTime.fromMillisecondsSinceEpoch(
          json['receivedTimestamp'] ?? json['received_timestamp'] ?? 0),
      train: json['train'] ?? '',
      direction: json['direction'] ?? json['dir'] ?? 0,
      speed: json['speed'] ?? '',
      position: json['position'] ?? json['pos'] ?? '',
      time: json['time'] ?? '',
      loco: json['loco'] ?? '',
      locoType: json['locoType'] ?? json['loco_type'] ?? '',
      lbjClass: json['lbjClass'] ?? json['lbj_class'] ?? '',
      route: json['route'] ?? '',
      positionInfo: json['positionInfo'] ?? json['position_info'] ?? '',
      rssi: (json['rssi'] ?? 0.0).toDouble(),
    );
  }

  factory TrainRecord.fromJsonString(String jsonString) {
    final json = jsonDecode(jsonString);
    return TrainRecord.fromJson(json);
  }

  Map<String, dynamic> toJson() {
    return {
      'uniqueId': uniqueId,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'receivedTimestamp': receivedTimestamp.millisecondsSinceEpoch,
      'train': train,
      'direction': direction,
      'speed': speed,
      'position': position,
      'time': time,
      'loco': loco,
      'loco_type': locoType,
      'lbj_class': lbjClass,
      'route': route,
      'position_info': positionInfo,
      'rssi': rssi,
    };
  }

  Map<String, dynamic> toDatabaseJson() {
    return {
      'uniqueId': uniqueId,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'receivedTimestamp': receivedTimestamp.millisecondsSinceEpoch,
      'train': train,
      'direction': direction,
      'speed': speed,
      'position': position,
      'time': time,
      'loco': loco,
      'locoType': locoType,
      'lbjClass': lbjClass,
      'route': route,
      'positionInfo': positionInfo,
      'rssi': rssi,
    };
  }

  factory TrainRecord.fromDatabaseJson(Map<String, dynamic> json) {
    return TrainRecord(
      uniqueId: json['uniqueId']?.toString() ?? '',
      timestamp:
          DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int? ?? 0),
      receivedTimestamp: DateTime.fromMillisecondsSinceEpoch(
          json['receivedTimestamp'] as int? ?? 0),
      train: json['train']?.toString() ?? '',
      direction: json['direction'] as int? ?? 0,
      speed: json['speed']?.toString() ?? '',
      position: json['position']?.toString() ?? '',
      time: json['time']?.toString() ?? '',
      loco: json['loco']?.toString() ?? '',
      locoType: json['locoType']?.toString() ?? '',
      lbjClass: json['lbjClass']?.toString() ?? '',
      route: json['route']?.toString() ?? '',
      positionInfo: json['positionInfo']?.toString() ?? '',
      rssi: (json['rssi'] as num?)?.toDouble() ?? 0.0,
    );
  }

  String get directionText {
    switch (direction) {
      case 0:
        return '上行';
      case 1:
        return '下行';
      default:
        return '未知';
    }
  }

  String get locoTypeText {
    if (locoType.isEmpty) return '未知';
    return locoType;
  }

  String get trainType {
    final lbjClassValue = lbjClass.isEmpty ? "NA" : lbjClass;
    return TrainTypeUtil.getTrainType(lbjClassValue, train) ?? '未知';
  }

  String? get locoInfo {
    return LocoInfoUtil.getLocoInfoDisplay(locoType, train);
  }

  String get fullTrainNumber {
    final lbjClassValue = lbjClass.trim();
    final trainValue = train.trim();

    if (trainValue == "<NUL>") {
      return "";
    }

    if (lbjClassValue.isEmpty || lbjClassValue == "NA") {
      return trainValue;
    } else {
      return "$lbjClassValue$trainValue";
    }
  }

  String get lbjClassText {
    if (lbjClass.isEmpty) return '未知';
    return lbjClass;
  }

  double get speedValue {
    try {
      return double.parse(speed.replaceAll(RegExp(r'[^\d.]'), ''));
    } catch (e) {
      return 0.0;
    }
  }

  String get speedUnit {
    if (speed.contains('km/h')) return 'km/h';
    if (speed.contains('m/s')) return 'm/s';
    return '';
  }

  String get formattedTime {
    return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}';
  }

  String get formattedDate {
    return '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}';
  }

  String get relativeTime {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return '刚刚';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}分钟前';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}小时前';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}天前';
    } else {
      return formattedDate;
    }
  }

  String get rssiDescription {
    if (rssi > -50) return '强';
    if (rssi > -70) return '中';
    if (rssi > -90) return '弱';
    return '无信号';
  }

  Color get rssiColor {
    if (rssi > -50) return Colors.green;
    if (rssi > -70) return Colors.orange;
    if (rssi > -90) return Colors.red;
    return Colors.grey;
  }

  Map<String, dynamic> toMap() {
    return {
      'uniqueId': uniqueId,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'receivedTimestamp': receivedTimestamp.millisecondsSinceEpoch,
      'train': train,
      'direction': direction,
      'speed': speed,
      'position': position,
      'time': time,
      'loco': loco,
      'locoType': locoType,
      'lbjClass': lbjClass,
      'route': route,
      'positionInfo': positionInfo,
      'rssi': rssi,
    };
  }

  Map<String, double> getCoordinates() {
    final parts = position.split(',');
    if (parts.length >= 2) {
      try {
        final lat = double.parse(parts[0].trim());
        final lng = double.parse(parts[1].trim());
        return {'lat': lat, 'lng': lng};
      } catch (e) {
        return {'lat': 0.0, 'lng': 0.0};
      }
    }
    return {'lat': 0.0, 'lng': 0.0};
  }

  TrainRecord copyWith({
    String? uniqueId,
    DateTime? timestamp,
    DateTime? receivedTimestamp,
    String? train,
    int? direction,
    String? speed,
    String? position,
    String? time,
    String? loco,
    String? locoType,
    String? lbjClass,
    String? route,
    String? positionInfo,
    double? rssi,
  }) {
    return TrainRecord(
      uniqueId: uniqueId ?? this.uniqueId,
      timestamp: timestamp ?? this.timestamp,
      receivedTimestamp: receivedTimestamp ?? this.receivedTimestamp,
      train: train ?? this.train,
      direction: direction ?? this.direction,
      speed: speed ?? this.speed,
      position: position ?? this.position,
      time: time ?? this.time,
      loco: loco ?? this.loco,
      locoType: locoType ?? this.locoType,
      lbjClass: lbjClass ?? this.lbjClass,
      route: route ?? this.route,
      positionInfo: positionInfo ?? this.positionInfo,
      rssi: rssi ?? this.rssi,
    );
  }

  @override
  String toString() {
    return 'TrainRecord(uniqueId: $uniqueId, train: $train, direction: $direction, speed: $speed, position: $position)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TrainRecord && other.uniqueId == uniqueId;
  }

  @override
  int get hashCode => uniqueId.hashCode;
}

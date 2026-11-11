import 'dart:math';
import 'package:fast_gbk/fast_gbk.dart';

const String lbjInfoAddr = "1234000";
const String lbjInfo2Addr = "1234002";
const String lbjSyncAddr = "1234008";
const int functionDown = 1;
const int functionUp = 3;

class LbjState {
  String train = "<NUL>";
  int direction = -1;
  String speed = "NUL";
  String positionKm = " <NUL>";
  String time = "<NUL>";
  String lbjClass = "NA";
  String loco = "<NUL>";
  String route = "********";

  String posLonDeg = "";
  String posLonMin = "";
  String posLatDeg = "";
  String posLatMin = "";

  String _info2Hex = "";

  void reset() {
    train = "<NUL>";
    direction = -1;
    speed = "NUL";
    positionKm = " <NUL>";
    time = "<NUL>";
    lbjClass = "NA";
    loco = "<NUL>";
    route = "********";
    posLonDeg = "";
    posLonMin = "";
    posLatDeg = "";
    posLatMin = "";
    _info2Hex = "";
  }

  String _recodeBCD(String numericStr) {
    return numericStr
        .replaceAll('.', 'A')
        .replaceAll('U', 'B')
        .replaceAll(' ', 'C')
        .replaceAll('-', 'D')
        .replaceAll(')', 'E')
        .replaceAll('(', 'F');
  }

  int _hexToChar(String hex1, String hex2) {
    final String hex = "$hex1$hex2";
    return int.tryParse(hex, radix: 16) ?? 0;
  }

  String _gbkToUtf8(List<int> gbkBytes) {
    try {
      final validBytes = gbkBytes.where((b) => b != 0).toList();
      return gbk.decode(validBytes);
    } catch (e) {
      return "";
    }
  }

  void updateFromRaw(String addr, int func, String numeric) {
    if (func == functionDown || func == functionUp) {
      direction = func;
    }
    switch (addr) {
      case lbjInfoAddr:
        final RegExp infoRegex = RegExp(r'^\s*(\S+)\s+(\S+)\s+(\S+)');
        final match = infoRegex.firstMatch(numeric);
        if (match != null) {
          train = match.group(1) ?? "<NUL>";
          speed = match.group(2) ?? "NUL";

          String pos = match.group(3)?.trim() ?? "";

          if (pos.isEmpty) {
            positionKm = " <NUL>";
          } else if (pos.length > 1) {
            positionKm =
                "${pos.substring(0, pos.length - 1)}.${pos.substring(pos.length - 1)}";
          } else {
            positionKm = "0.$pos";
          }
        }
        break;

      case lbjInfo2Addr:
        String buffer = numeric;
        if (buffer.length < 50) return;
        _info2Hex = _recodeBCD(buffer);

        if (_info2Hex.length >= 4) {
          try {
            List<int> classBytes = [
              _hexToChar(_info2Hex[0], _info2Hex[1]),
              _hexToChar(_info2Hex[2], _info2Hex[3]),
            ];
            lbjClass = String.fromCharCodes(classBytes
                .where((b) => b > 0x1F && b < 0x7F && b != 0x22 && b != 0x2C));
          // ignore: empty_catches
          } catch (e) {}
        }
        if (buffer.length >= 12) loco = buffer.substring(4, 12);

        List<int> routeBytes = List<int>.filled(17, 0);

        if (_info2Hex.length >= 18) {
          try {
            routeBytes[0] = _hexToChar(_info2Hex[14], _info2Hex[15]);
            routeBytes[1] = _hexToChar(_info2Hex[16], _info2Hex[17]);
          // ignore: empty_catches
          } catch (e) {}
        }

        if (_info2Hex.length >= 22) {
          try {
            routeBytes[2] = _hexToChar(_info2Hex[18], _info2Hex[19]);
            routeBytes[3] = _hexToChar(_info2Hex[20], _info2Hex[21]);
          // ignore: empty_catches
          } catch (e) {}
        }

        if (_info2Hex.length >= 30) {
          try {
            routeBytes[4] = _hexToChar(_info2Hex[22], _info2Hex[23]);
            routeBytes[5] = _hexToChar(_info2Hex[24], _info2Hex[25]);
            routeBytes[6] = _hexToChar(_info2Hex[26], _info2Hex[27]);
            routeBytes[7] = _hexToChar(_info2Hex[28], _info2Hex[29]);
          // ignore: empty_catches
          } catch (e) {}
        }
        route = _gbkToUtf8(routeBytes);

        if (buffer.length >= 39) {
          posLonDeg = buffer.substring(30, 33);
          posLonMin = "${buffer.substring(33, 35)}.${buffer.substring(35, 39)}";
        }
        if (buffer.length >= 47) {
          posLatDeg = buffer.substring(39, 41);
          posLatMin = "${buffer.substring(41, 43)}.${buffer.substring(43, 47)}";
        }
        break;

      case lbjSyncAddr:
        if (numeric.length >= 5) {
          time = "${numeric.substring(1, 3)}:${numeric.substring(3, 5)}";
        }
        break;
    }
  }

  double _convertMagSqToRssi(double magsqRaw) {
    if (magsqRaw <= 0) return -120.0;
    double rssi = 10 * log(magsqRaw) / log(10);
    return rssi.clamp(-120.0, 0.0);
  }

  Map<String, dynamic> toTrainRecordJson([double? magsqRaw]) {
    final now = DateTime.now();
    final double finalRssi =
        magsqRaw == null ? 0.0 : _convertMagSqToRssi(magsqRaw);

    double? latitude;
    if (posLatDeg.isNotEmpty && posLatMin.isNotEmpty) {
      final deg = double.tryParse(posLatDeg);
      final min = double.tryParse(posLatMin);
      if (deg != null && min != null) latitude = deg + min / 60;
    }
    double? longitude;
    if (posLonDeg.isNotEmpty && posLonMin.isNotEmpty) {
      final deg = double.tryParse(posLonDeg);
      final min = double.tryParse(posLonMin);
      if (deg != null && min != null) longitude = deg + min / 60;
    }

    String kmPosition = positionKm.replaceAll(' <NUL>', '');
    final trainDigits = train.replaceAll('<NUL>', '');
    final classText = lbjClass.replaceAll('NA', '').trim();

    final jsonData = {
      'uniqueId': '${now.millisecondsSinceEpoch}_${Random().nextInt(9999)}',
      'receivedTimestamp': now.millisecondsSinceEpoch,
      'timestamp': now.millisecondsSinceEpoch,
      'rssi': finalRssi,
      'trainNumber':
          classText.isEmpty ? trainDigits : '$classText$trainDigits',
      'rawLocoNumber': loco.replaceAll('<NUL>', ''),
      'speedKmh': speed.replaceAll('NUL', ''),
      'kilometerMark': kmPosition,
      'route': route.replaceAll('********', ''),
      'latitude': latitude,
      'longitude': longitude,
      'directionCode': (direction == 1 || direction == 3) ? direction : 0,
    };
    return jsonData;
  }
}

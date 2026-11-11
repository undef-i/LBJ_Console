import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lbjconsole/services/ffsk_protocol.dart';
import 'package:lbjconsole/services/ffsk_demod.dart';
import 'package:lbjconsole/services/pocsag_demod.dart';
import 'package:lbjconsole/services/sample_frames.dart';

Float32List _audio(Int16List pcm) {
  final out = Float32List(pcm.length);
  for (var i = 0; i < pcm.length; i++) {
    out[i] = pcm[i] / 32768.0;
  }
  return out;
}

void main() {
  loadLocoModelNames('239,HXD3C\n240,HXD1D\n');

  test('lbj sample frames decode through the mic demodulator', () {
    final info2 = lbjInfo2(loco: '23900001', lat: 39.9042, lng: 116.4074);
    for (final up in [false, true]) {
      final d = MicDemod();
      final pcm = lbjSamplePcm(
        up: up,
        sync: '0080500000',
        info: '7001 085 1230',
        info2: info2,
      );
      for (var at = 0; at < pcm.length; at += 4800) {
        final end = at + 4800 > pcm.length ? pcm.length : at + 4800;
        d.processSamples(Int16List.sublistView(pcm, at, end));
      }
      expect(d.messages.length, 3);
      expect(d.messages[0].address, 1234008);
      expect(d.messages[0].content, '0080500000');
      expect(d.messages[1].address, 1234000);
      expect(d.messages[1].function, up ? 3 : 1);
      expect(d.messages[1].content.trim(), '7001 085 1230');
      expect(d.messages[2].address, 1234002);
      expect(d.messages[2].content.trim(), info2);
    }
  });

  test('tdcs sample frame decodes through the ffsk decoder', () {
    final d = FfskDecoder();
    final messages = d.feed(_audio(ffskSamplePcm(tdcsSampleFrame(
      shared: true,
      serial: 5,
      speed: 100,
      weight: 4200,
      length: 60.5,
      cars: 50,
    ))));
    expect(messages.length, 1);
    final m = messages.single as FfskTdcs;
    expect(m.trainNumber, 7001);
    expect(m.trainPrefix, 'G');
    expect(m.locoModel, 'HXD3C');
    expect(m.locoSerial, '0001');
    expect(m.speedKmh, 100);
    expect(m.weightTonnes, 4200);
    expect(m.carCount, 50);
    expect(m.stationNo, 130);
    expect(m.segmentNo, 241);
    expect(m.driverId, 4309870);
  });

  test('alarm sample frames decode through the ffsk decoder', () {
    final now = DateTime(2026, 11, 11, 8, 5, 30);
    final train = FfskDecoder().feed(_audio(ffskSamplePcm(alarmSampleFrame(0, now))));
    expect(train.length, 1);
    final a = train.single as FfskAlarm;
    expect(a.function, 1);
    expect(a.train, 'G7001');
    expect(a.loco, '23900001');
    expect(a.kilometer, 1161.011);
    expect(a.sendTime, now);
    final ground =
        FfskDecoder().feed(_audio(ffskSamplePcm(alarmSampleFrame(4, now))));
    expect(ground.length, 1);
    final g = ground.single as FfskAlarm;
    expect(g.function, 5);
    expect(g.lineName, '京沪线');
    final test = FfskDecoder().feed(_audio(ffskSamplePcm(alarmSampleFrame(7, now))));
    expect(test.length, 1);
    final t = test.single as FfskAlarm;
    expect(t.function, 8);
    expect(t.loco, '23900001');
    expect(t.detail, contains('24.0 V'));
  });

  test('klw sample frame decodes through the ffsk decoder', () {
    final d = FfskDecoder();
    final messages = d.feed(_audio(ffskSamplePcm(
        klwSampleFrame(pairA: true, command: 0x94, pressure: 486))));
    expect(messages.length, 1);
    final m = messages.single as FfskKlw;
    expect(m.locoDisplay, 'HXD3C 0001');
    expect(m.tail, '880123');
    expect(m.command, 0x94);
    expect(m.pressure, 486);
  });
}

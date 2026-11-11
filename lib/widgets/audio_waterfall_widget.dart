import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:lbjconsole/services/audio_input_service.dart';
import 'package:lbjconsole/services/demod_worker.dart';

const int _waterfallTotalWidth = 500;
const int _waterfallHeight = 500;

int _intensityToArgb(double intensity) {
  Color color;
  if (intensity < 0.2) {
    color = Color.lerp(
      const Color(0xFF000033),
      const Color(0xFF0000FF),
      intensity / 0.2,
    )!;
  } else if (intensity < 0.4) {
    color = Color.lerp(
      const Color(0xFF0000FF),
      const Color(0xFF00FFFF),
      (intensity - 0.2) / 0.2,
    )!;
  } else if (intensity < 0.6) {
    color = Color.lerp(
      const Color(0xFF00FFFF),
      const Color(0xFF00FF00),
      (intensity - 0.4) / 0.2,
    )!;
  } else if (intensity < 0.8) {
    color = Color.lerp(
      const Color(0xFF00FF00),
      const Color(0xFFFFFF00),
      (intensity - 0.6) / 0.2,
    )!;
  } else {
    color = Color.lerp(
      const Color(0xFFFFFF00),
      const Color(0xFFFF0000),
      (intensity - 0.8) / 0.2,
    )!;
  }
  return ((color.a * 255.0).round() << 24) |
      ((color.r * 255.0).round() << 16) |
      ((color.g * 255.0).round() << 8) |
      (color.b * 255.0).round();
}

final List<int> _colorLUT = List.generate(
  256,
  (i) => _intensityToArgb(i / 255.0),
  growable: false,
);

Float32List poolSpectrumToWidth(Float32List bins, int width) {
  final out = Float32List(width);
  if (bins.isEmpty || width <= 0) return out;
  for (var c = 0; c < width; c++) {
    var start = c * bins.length ~/ width;
    var end = (c + 1) * bins.length ~/ width;
    if (end <= start) end = start + 1;
    var best = bins[start];
    for (var i = start + 1; i < end && i < bins.length; i++) {
      if (bins[i] > best) best = bins[i];
    }
    out[c] = best;
  }
  return out;
}

class SpectrumStrip {
  SpectrumStrip(this.band, this.width)
    : pixels = Uint32List(width * _waterfallHeight) {
    for (var i = 0; i < pixels.length; i++) {
      pixels[i] = 0xFF000033;
    }
  }

  final String band;
  final int width;
  final Uint32List pixels;
  ui.Image? image;
  Float32List latest = Float32List(0);

  void append(Float32List bins) {
    latest = bins;
    final pooled = poolSpectrumToWidth(bins, width);
    pixels.setRange(width, pixels.length, pixels, 0);
    for (var i = 0; i < width; i++) {
      pixels[i] = _colorLUT[(pooled[i].clamp(0.0, 1.0) * 255).toInt()];
    }
  }

  Future<void> rebuild() async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels.buffer.asUint8List(),
      width,
      _waterfallHeight,
      ui.PixelFormat.bgra8888,
      completer.complete,
    );
    final newImage = await completer.future;
    image?.dispose();
    image = newImage;
  }

  void dispose() {
    image?.dispose();
    image = null;
  }
}

class SpectrumStore {
  SpectrumStore._();
  static final SpectrumStore instance = SpectrumStore._();

  final Map<String, SpectrumStrip> strips = {};
  String currentBand = '';

  SpectrumStrip stripFor(String band) {
    return strips.putIfAbsent(
      band,
      () => SpectrumStrip(
        band,
        band == 'audio' ? _waterfallTotalWidth : _waterfallTotalWidth ~/ 3,
      ),
    );
  }
}

class AudioWaterfallWidget extends StatefulWidget {
  const AudioWaterfallWidget({super.key, required this.source});

  final String source;

  @override
  State<AudioWaterfallWidget> createState() => _AudioWaterfallWidgetState();
}

class _AudioWaterfallWidgetState extends State<AudioWaterfallWidget> {
  Timer? _updateTimer;
  bool _ticking = false;
  String _signature = '';

  @override
  void initState() {
    super.initState();
    _updateTimer = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => _tick(),
    );
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  Future<void> _tick() async {
    if (_ticking) return;
    _ticking = true;
    try {
      final frame = await AudioInputService().getSpectrum();
      if (!mounted) return;
      final store = SpectrumStore.instance;
      if (widget.source != 'audio' && frame.band == 'audio') {
        return;
      }
      if (frame.band == 'audio') {
        store.stripFor('audio');
      } else {
        for (final band in AudioInputService().activeProtocols) {
          store.stripFor(band);
        }
      }
      final enabled = frame.band == 'audio'
          ? const ['audio']
          : AudioInputService().activeProtocols;
      final signature = enabled.join(',');
      if (signature != _signature) {
        _signature = signature;
        setState(() {});
      }
      final strip = store.strips[frame.band];
      if (strip == null) return;
      strip.append(frame.values);
      store.currentBand = frame.band;
      await strip.rebuild();
      if (mounted) setState(() {});
    } on Exception catch (_) {
      return;
    } finally {
      _ticking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = SpectrumStore.instance;
    final shown = _signature.split(',');
    final strips = [
      for (final band in const ['audio', 'lbj', 'klw', 'tdcs'])
        if (shown.contains(band) && store.strips[band] != null)
          store.strips[band]!,
    ];
    final multi = strips.length > 1;
    final anySpectrum = strips.any((s) => s.latest.isNotEmpty);
    final anyImage = strips.any((s) => s.image != null);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 80,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.black,
            border: Border(
              left: BorderSide(
                color: Colors.cyan.withValues(alpha: 0.3),
                width: 2,
              ),
              right: BorderSide(
                color: Colors.cyan.withValues(alpha: 0.3),
                width: 2,
              ),
              top: BorderSide(
                color: Colors.cyan.withValues(alpha: 0.3),
                width: 2,
              ),
            ),
          ),
          child: !anySpectrum
              ? const SizedBox.shrink()
              : Row(
                  children: [
                    for (var i = 0; i < strips.length; i++)
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(
                              left: i == 0
                                  ? BorderSide.none
                                  : BorderSide(
                                      color: Colors.cyan.withValues(alpha: 0.3),
                                      width: 1,
                                    ),
                            ),
                          ),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: strips[i].latest.isEmpty
                                    ? const SizedBox.shrink()
                                    : CustomPaint(
                                        painter: _SpectrumPainter(
                                          strips[i].latest,
                                        ),
                                      ),
                              ),
                              if (multi)
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  top: 2,
                                  child: Text(
                                    DemodWorker.protoFreqLabel[strips[i]
                                            .band] ??
                                        '',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: strips[i].band == store.currentBand
                                          ? Colors.cyan
                                          : Colors.white60,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        Container(
          height: 100,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.black,
            border: Border(
              left: BorderSide(
                color: Colors.cyan.withValues(alpha: 0.3),
                width: 2,
              ),
              right: BorderSide(
                color: Colors.cyan.withValues(alpha: 0.3),
                width: 2,
              ),
              bottom: BorderSide(
                color: Colors.cyan.withValues(alpha: 0.3),
                width: 2,
              ),
            ),
          ),
          child: !anyImage
              ? const SizedBox.shrink()
              : Row(
                  children: [
                    for (var i = 0; i < strips.length; i++)
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(
                              left: i == 0
                                  ? BorderSide.none
                                  : BorderSide(
                                      color: Colors.cyan.withValues(alpha: 0.3),
                                      width: 1,
                                    ),
                            ),
                          ),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: strips[i].image == null
                                    ? const SizedBox.shrink()
                                    : CustomPaint(
                                        painter: _WaterfallImagePainter(
                                          strips[i].image!,
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _SpectrumPainter extends CustomPainter {
  final List<double> spectrum;
  _SpectrumPainter(this.spectrum);

  @override
  void paint(Canvas canvas, Size size) {
    if (spectrum.isEmpty) return;

    final path = Path();
    final binWidth = size.width / spectrum.length;

    for (int i = 0; i < spectrum.length; i++) {
      final x = i * binWidth;
      final y = size.height - (spectrum[i].clamp(0.0, 1.0) * size.height);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.cyan
        ..strokeWidth = 0.5
        ..style = PaintingStyle.stroke
        ..isAntiAlias = true
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SpectrumPainter old) => true;
}

class _WaterfallImagePainter extends CustomPainter {
  final ui.Image image;
  _WaterfallImagePainter(this.image);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..filterQuality = FilterQuality.none,
    );
  }

  @override
  bool shouldRepaint(_WaterfallImagePainter old) => old.image != image;
}

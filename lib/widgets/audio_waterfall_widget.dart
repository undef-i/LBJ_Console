import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class _WaterfallCache {
  static final _WaterfallCache instance = _WaterfallCache._();
  _WaterfallCache._();

  static const int waterfallWidth = 500;
  static const int waterfallHeight = 500;

  Uint32List? pixels;
  late List<int> colorLUT;

  void initialize() {
    if (pixels == null) {
      pixels = Uint32List(waterfallWidth * waterfallHeight);
      for (int i = 0; i < pixels!.length; i++) {
        pixels![i] = 0xFF000033;
      }
      _buildColorLUT();
    }
  }

  void _buildColorLUT() {
    colorLUT = List.filled(256, 0);
    for (int i = 0; i < 256; i++) {
      final intensity = i / 255.0;
      final color = _intensityToColor(intensity);
      colorLUT[i] = ((color.a * 255.0).round() << 24) |
          ((color.r * 255.0).round() << 16) |
          ((color.g * 255.0).round() << 8) |
          (color.b * 255.0).round();
    }
  }

  Color _intensityToColor(double intensity) {
    if (intensity < 0.2) {
      return Color.lerp(
          const Color(0xFF000033), const Color(0xFF0000FF), intensity / 0.2)!;
    } else if (intensity < 0.4) {
      return Color.lerp(const Color(0xFF0000FF), const Color(0xFF00FFFF),
          (intensity - 0.2) / 0.2)!;
    } else if (intensity < 0.6) {
      return Color.lerp(const Color(0xFF00FFFF), const Color(0xFF00FF00),
          (intensity - 0.4) / 0.2)!;
    } else if (intensity < 0.8) {
      return Color.lerp(const Color(0xFF00FF00), const Color(0xFFFFFF00),
          (intensity - 0.6) / 0.2)!;
    } else {
      return Color.lerp(const Color(0xFFFFFF00), const Color(0xFFFF0000),
          (intensity - 0.8) / 0.2)!;
    }
  }
}

class AudioWaterfallWidget extends StatefulWidget {
  const AudioWaterfallWidget({super.key});

  @override
  State<AudioWaterfallWidget> createState() => _AudioWaterfallWidgetState();
}

class _AudioWaterfallWidgetState extends State<AudioWaterfallWidget> {
  static const platform = MethodChannel('org.noxylva.lbjconsole/audio_input');

  final _cache = _WaterfallCache.instance;
  ui.Image? _waterfallImage;
  List<double> _currentSpectrum = [];

  Timer? _updateTimer;
  bool _imageNeedsUpdate = false;

  @override
  void initState() {
    super.initState();
    _cache.initialize();
    _startUpdating();
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _waterfallImage?.dispose();
    super.dispose();
  }

  void _startUpdating() {
    _updateTimer =
        Timer.periodic(const Duration(milliseconds: 50), (timer) async {
      try {
        final result = await platform.invokeMethod('getSpectrum');
        if (result != null && result is List && mounted) {
          final fftData = result.cast<double>();

          final pixels = _cache.pixels!;
          pixels.setRange(
              _WaterfallCache.waterfallWidth, pixels.length, pixels, 0);

          for (int i = 0;
              i < _WaterfallCache.waterfallWidth && i < fftData.length;
              i++) {
            final intensity = (fftData[i].clamp(0.0, 1.0) * 255).toInt();
            pixels[i] = _cache.colorLUT[intensity];
          }

          _currentSpectrum = fftData;
          _imageNeedsUpdate = true;

          if (_imageNeedsUpdate) {
            _rebuildImage();
          }
        }
      // ignore: empty_catches
      } catch (e) {}
    });
  }

  Future<void> _rebuildImage() async {
    _imageNeedsUpdate = false;

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      _cache.pixels!.buffer.asUint8List(),
      _WaterfallCache.waterfallWidth,
      _WaterfallCache.waterfallHeight,
      ui.PixelFormat.bgra8888,
      (image) => completer.complete(image),
    );

    final newImage = await completer.future;
    if (mounted) {
      setState(() {
        _waterfallImage?.dispose();
        _waterfallImage = newImage;
      });
    } else {
      newImage.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 80,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.black,
            border: Border(
              left: BorderSide(color: Colors.cyan.withValues(alpha: 0.3), width: 2),
              right: BorderSide(color: Colors.cyan.withValues(alpha: 0.3), width: 2),
              top: BorderSide(color: Colors.cyan.withValues(alpha: 0.3), width: 2),
            ),
          ),
          child: _currentSpectrum.isEmpty
              ? const Center(
                  child: CircularProgressIndicator(
                      color: Colors.cyan, strokeWidth: 2))
              : CustomPaint(painter: _SpectrumPainter(_currentSpectrum)),
        ),
        Container(
          height: 100,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.black,
            border: Border(
              left: BorderSide(color: Colors.cyan.withValues(alpha: 0.3), width: 2),
              right: BorderSide(color: Colors.cyan.withValues(alpha: 0.3), width: 2),
              bottom: BorderSide(color: Colors.cyan.withValues(alpha: 0.3), width: 2),
            ),
          ),
          child: _waterfallImage == null
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.cyan))
              : CustomPaint(painter: _WaterfallImagePainter(_waterfallImage!)),
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
          ..strokeJoin = StrokeJoin.round);
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

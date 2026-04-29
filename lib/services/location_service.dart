import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  static LocationService get instance => _instance;

  LatLng? _currentLocation;
  Timer? _locationTimer;
  bool _isLocationPermissionGranted = false;
  final StreamController<LatLng?> _locationStreamController =
      StreamController<LatLng?>.broadcast();

  Stream<LatLng?> get locationStream => _locationStreamController.stream;
  LatLng? get currentLocation => _currentLocation;
  bool get isLocationPermissionGranted => _isLocationPermissionGranted;

  Future<void> initialize() async {
    await _requestLocationPermission();
    if (_isLocationPermissionGranted) {
      await _getCurrentLocation();
      _startLocationUpdates();
    }
  }

  Future<void> _requestLocationPermission() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        return;
      }

      _isLocationPermissionGranted = true;
    // ignore: empty_catches
    } catch (e) {}
  }

  Future<void> _getCurrentLocation() async {
    if (!_isLocationPermissionGranted) return;

    try {
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      _currentLocation = LatLng(position.latitude, position.longitude);
      _locationStreamController.add(_currentLocation);
    // ignore: empty_catches
    } catch (e) {}
  }

  void _startLocationUpdates() {
    _locationTimer?.cancel();
    _locationTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isLocationPermissionGranted) {
        _getCurrentLocation();
      }
    });
  }

  Future<void> forceUpdateLocation() async {
    if (!_isLocationPermissionGranted) {
      await _requestLocationPermission();
    }
    await _getCurrentLocation();
  }

  void dispose() {
    _locationTimer?.cancel();
    _locationStreamController.close();
  }
}

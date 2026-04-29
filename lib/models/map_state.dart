class MapState {
  final double zoom;
  final double centerLat;
  final double centerLng;
  final double bearing;

  MapState({
    required this.zoom,
    required this.centerLat,
    required this.centerLng,
    required this.bearing,
  });

  Map<String, dynamic> toJson() {
    return {
      'zoom': zoom,
      'centerLat': centerLat,
      'centerLng': centerLng,
      'bearing': bearing,
    };
  }

  factory MapState.fromJson(Map<String, dynamic> json) {
    return MapState(
      zoom: json['zoom']?.toDouble() ?? 10.0,
      centerLat: json['centerLat']?.toDouble() ?? 39.9042,
      centerLng: json['centerLng']?.toDouble() ?? 116.4074,
      bearing: json['bearing']?.toDouble() ?? 0.0,
    );
  }

  MapState copyWith({
    double? zoom,
    double? centerLat,
    double? centerLng,
    double? bearing,
  }) {
    return MapState(
      zoom: zoom ?? this.zoom,
      centerLat: centerLat ?? this.centerLat,
      centerLng: centerLng ?? this.centerLng,
      bearing: bearing ?? this.bearing,
    );
  }

  @override
  String toString() {
    return 'MapState(zoom: $zoom, centerLat: $centerLat, centerLng: $centerLng, bearing: $bearing)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MapState &&
        other.zoom == zoom &&
        other.centerLat == centerLat &&
        other.centerLng == centerLng &&
        other.bearing == bearing;
  }

  @override
  int get hashCode {
    return zoom.hashCode ^
        centerLat.hashCode ^
        centerLng.hashCode ^
        bearing.hashCode;
  }
}

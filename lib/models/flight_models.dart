import 'dart:math';

class Flight {
  final int? id;
  final DateTime startTime;
  final DateTime? endTime;
  final int? duration; // seconds
  final double? maxAltitude; // meters
  final double? totalDistance; // meters
  final double? maxPositiveG;
  final double? maxNegativeG;
  final String? notes;

  Flight({
    this.id,
    required this.startTime,
    this.endTime,
    this.duration,
    this.maxAltitude,
    this.totalDistance,
    this.maxPositiveG,
    this.maxNegativeG,
    this.notes,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'start_time': startTime.millisecondsSinceEpoch,
      'end_time': endTime?.millisecondsSinceEpoch,
      'duration': duration,
      'max_altitude': maxAltitude,
      'total_distance': totalDistance,
      'max_positive_g': maxPositiveG,
      'max_negative_g': maxNegativeG,
      'notes': notes,
    };
  }

  factory Flight.fromMap(Map<String, dynamic> map) {
    return Flight(
      id: map['id'] as int?,
      startTime: DateTime.fromMillisecondsSinceEpoch(map['start_time'] as int),
      endTime: map['end_time'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['end_time'] as int)
          : null,
      duration: map['duration'] as int?,
      maxAltitude: map['max_altitude'] as double?,
      totalDistance: map['total_distance'] as double?,
      maxPositiveG: map['max_positive_g'] as double?,
      maxNegativeG: map['max_negative_g'] as double?,
      notes: map['notes'] as String?,
    );
  }

  Flight copyWith({
    int? id,
    DateTime? startTime,
    DateTime? endTime,
    int? duration,
    double? maxAltitude,
    double? totalDistance,
    double? maxPositiveG,
    double? maxNegativeG,
    String? notes,
  }) {
    return Flight(
      id: id ?? this.id,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      duration: duration ?? this.duration,
      maxAltitude: maxAltitude ?? this.maxAltitude,
      totalDistance: totalDistance ?? this.totalDistance,
      maxPositiveG: maxPositiveG ?? this.maxPositiveG,
      maxNegativeG: maxNegativeG ?? this.maxNegativeG,
      notes: notes ?? this.notes,
    );
  }
}

class SensorDataPoint {
  final int? id;
  final int flightId;
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final double? altitude;
  final double? speed;
  final double? accelX;
  final double? accelY;
  final double? accelZ;
  final double? gForce;
  final double? heading;

  SensorDataPoint({
    this.id,
    required this.flightId,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.speed,
    this.accelX,
    this.accelY,
    this.accelZ,
    this.gForce,
    this.heading,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'flight_id': flightId,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
      'speed': speed,
      'accel_x': accelX,
      'accel_y': accelY,
      'accel_z': accelZ,
      'g_force': gForce,
      'heading': heading,
    };
  }

  factory SensorDataPoint.fromMap(Map<String, dynamic> map) {
    return SensorDataPoint(
      id: map['id'] as int?,
      flightId: map['flight_id'] as int,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      latitude: map['latitude'] as double,
      longitude: map['longitude'] as double,
      altitude: map['altitude'] as double?,
      speed: map['speed'] as double?,
      accelX: map['accel_x'] as double?,
      accelY: map['accel_y'] as double?,
      accelZ: map['accel_z'] as double?,
      gForce: map['g_force'] as double?,
      heading: map['heading'] as double?,
    );
  }

  String toCsvRow() {
    return '${timestamp.toIso8601String()},$latitude,$longitude,'
        '${altitude ?? ''},'
        '${speed ?? ''},'
        '${accelX ?? ''},'
        '${accelY ?? ''},'
        '${accelZ ?? ''},'
        '${gForce ?? ''},'
        '${heading ?? ''}';
  }

  static String csvHeader() {
    return 'timestamp,latitude,longitude,altitude,speed,'
        'accel_x,accel_y,accel_z,g_force,heading';
  }

  // Calculate distance to another point using Haversine formula
  double distanceTo(SensorDataPoint other) {
    const earthRadius = 6371000.0; // meters
    final lat1 = latitude * pi / 180;
    final lat2 = other.latitude * pi / 180;
    final dLat = (other.latitude - latitude) * pi / 180;
    final dLon = (other.longitude - longitude) * pi / 180;

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c;
  }
}

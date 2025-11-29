import 'dart:async';
import 'dart:math';
import 'dart:io' show Platform;
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/flight_models.dart';
import 'database_service.dart';

class RecordingService {
  static final RecordingService instance = RecordingService._init();
  RecordingService._init();

  bool _isRecording = false;
  int? _currentFlightId;
  Flight? _currentFlight;

  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<MagnetometerEvent>? _magnetometerSubscription;
  StreamSubscription<BarometerEvent>? _barometerSubscription;

  Position? _lastPosition;
  AccelerometerEvent? _lastAccelerometer;
  double? _lastHeading;
  double? _lastPresure;

  // GPS accuracy tracking
  bool _hasGoodGpsFix = false;
  int _gpsReadings = 0;

  final List<SensorDataPoint> _dataBuffer = [];
  Timer? _bufferTimer;
  Timer? _sensorCollectionTimer;
  static const int _bufferSize = 10; // Save every 10 points
  static const Duration _bufferInterval = Duration(seconds: 5);

  // Current values for UI
  final StreamController<Map<String, dynamic>> _currentDataController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get currentDataStream =>
      _currentDataController.stream;

  bool get isRecording => _isRecording;
  Flight? get currentFlight => _currentFlight;
  double? get currentSpeed => _lastPosition?.speed;

  Future<bool> startRecording() async {
    if (_isRecording) return false;

    // Check and request permissions
    bool hasPermission = await _checkPermissions();
    if (!hasPermission) {
      throw Exception('Location permissions not granted');
    }

    // Enable wake lock to keep screen on and GPS active
    try {
      await WakelockPlus.enable();
    } catch (e) {
      print('Failed to enable wakelock: $e');
    }

    // Create new flight
    final flight = Flight(
      startTime: DateTime.now(),
    );

    final flightId = await DatabaseService.instance.createFlight(flight);
    _currentFlightId = flightId;
    _currentFlight = flight.copyWith(id: flightId);
    _hasGoodGpsFix = false;
    _gpsReadings = 0;

    _isRecording = true;
    _startListening();

    return true;
  }

  Future<Flight?> stopRecording() async {
    if (!_isRecording || _currentFlightId == null) return null;

    _isRecording = false;
    _stopListening();

    // Disable wake lock
    try {
      await WakelockPlus.disable();
    } catch (e) {
      print('Failed to disable wakelock: $e');
    }

    // Save any remaining buffered data
    if (_dataBuffer.isNotEmpty) {
      await _saveBufferedData();
    }

    // Update flight with end time
    final updatedFlight = _currentFlight!.copyWith(
      endTime: DateTime.now(),
    );
    await DatabaseService.instance.updateFlight(updatedFlight);

    // Calculate and save statistics
    final flightWithStats =
        await DatabaseService.instance.calculateFlightStats(_currentFlightId!);
    await DatabaseService.instance.updateFlight(flightWithStats);

    final result = flightWithStats;
    _currentFlightId = null;
    _currentFlight = null;

    return result;
  }

  void _startListening() {
    // GPS tracking - Platform-specific settings for continuous recording
    final LocationSettings locationSettings;
    
    if (Platform.isAndroid) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        forceLocationManager: true, // Use location manager instead of FusedLocationProvider
        intervalDuration: const Duration(seconds: 1),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: "Flight Recorder is recording your flight",
          notificationTitle: "Recording Flight",
          enableWakeLock: true,
        ),
      );
    } else if (Platform.isIOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        activityType: ActivityType.otherNavigation,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      );
    } else {
      // Fallback for other platforms (shouldn't happen in production)
      locationSettings = const LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
    );
    }

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      _onPositionUpdate,
      onError: (error) {
        print('GPS Error: $error');
        // Continue running even if GPS has issues
      },
      cancelOnError: false,
    );

    // Accelerometer (~50 Hz)
    _accelerometerSubscription = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 20), // ~50 Hz
    ).listen(
      _onAccelerometerUpdate,
      onError: (error) {
        print('Accelerometer Error: $error');
      },
      cancelOnError: false,
    );

    // Magnetometer for heading (~10 Hz)
    _magnetometerSubscription = magnetometerEventStream(
      samplingPeriod: const Duration(milliseconds: 100), // ~10 Hz
    ).listen(
      _onMagnetometerUpdate,
      onError: (error) {
        print('Magnetometer Error: $error');
      },
      cancelOnError: false,
    );

    // Barometer for presure (~1 Hz)
    _barometerSubscription = barometerEventStream(
      samplingPeriod: const Duration(seconds: 1), // ~1 Hz
    ).listen(
      _onBarometerUpdate,
      onError: (error) {
        print('Barometer Error: $error');
      },
      cancelOnError: false,
    );

    // Start buffer timer
    _bufferTimer = Timer.periodic(_bufferInterval, (_) => _saveBufferedData());

    // Start sensor collection timer (collect every second even without GPS updates)
    _sensorCollectionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _collectDataPoint();
    });

    // Get initial position to kickstart GPS
    _getInitialPosition();
  }

  Future<void> _getInitialPosition() async {
    try {
      final position = await Geolocator.getCurrentPosition();
      _lastPosition = position;
      _collectDataPoint();
    } catch (e) {
      print('Error getting initial position: $e');
      // Not critical, stream will continue trying
    }
  }

  void _stopListening() {
    _positionSubscription?.cancel();
    _accelerometerSubscription?.cancel();
    _magnetometerSubscription?.cancel();
    _barometerSubscription?.cancel();
    _bufferTimer?.cancel();
    _sensorCollectionTimer?.cancel();

    _positionSubscription = null;
    _accelerometerSubscription = null;
    _magnetometerSubscription = null;
    _barometerSubscription = null;
    _bufferTimer = null;
    _sensorCollectionTimer = null;
  }

  void _onPositionUpdate(Position position) {
    _gpsReadings++;

    // Check GPS accuracy - accuracy is in meters
    // Good GPS fix: accuracy < 20m and at least 5 readings
    if (position.accuracy < 20 && _gpsReadings >= 5) {
      _hasGoodGpsFix = true;
    }

    _lastPosition = position;

    // Calculate heading from GPS bearing (more accurate than magnetometer)
    if (position.speed > 1.0) {
      // Only use bearing when moving > 1 m/s
      _lastHeading = position.heading;
    }
  }

  void _onAccelerometerUpdate(AccelerometerEvent event) {
    _lastAccelerometer = event;
  }

  void _onMagnetometerUpdate(MagnetometerEvent event) {
    // Simple heading calculation (more accurate would use rotation matrix)
    if (_lastPosition != null && _lastPosition!.speed <= 1.0) {
      _lastHeading = atan2(event.y, event.x) * (180 / pi);
      if (_lastHeading! < 0) _lastHeading = _lastHeading! + 360;
    }
  }

  void _onBarometerUpdate(BarometerEvent event) {
    // Simple heading calculation (more accurate would use rotation matrix)
    _lastPresure = event.pressure;
  }

  void _collectDataPoint() {
    if (!_isRecording || _currentFlightId == null) {
      return;
    }

    // If we don't have GPS yet, just update UI with sensor data but don't save
    if (_lastPosition == null) {
      final gForce = _lastAccelerometer != null
          ? _calculateGForce(
              _lastAccelerometer!.x,
              _lastAccelerometer!.y,
              _lastAccelerometer!.z,
            )
          : null;

      // Emit current data for UI (without GPS)
      _currentDataController.add({
        'altitude': null,
        'speed': null,
        'gForce': gForce,
        'heading': _lastHeading,
        'presure': _lastPresure,
        'gpsAccuracy': null,
        'hasGoodFix': false,
      });
      return;
    }

    final gForce = _lastAccelerometer != null
        ? _calculateGForce(
            _lastAccelerometer!.x,
            _lastAccelerometer!.y,
            _lastAccelerometer!.z,
          )
        : null;

    // Only save data with reasonable GPS accuracy (< 50m)
    if (_lastPosition!.accuracy < 50) {
      final dataPoint = SensorDataPoint(
        flightId: _currentFlightId!,
        timestamp: DateTime.now(),
        latitude: _lastPosition!.latitude,
        longitude: _lastPosition!.longitude,
        altitude: _lastPosition!.altitude,
        speed: _lastPosition!.speed,
        accelX: _lastAccelerometer?.x,
        accelY: _lastAccelerometer?.y,
        accelZ: _lastAccelerometer?.z,
        gForce: gForce,
        heading: _lastHeading,
        presure: _lastPresure,
      );

      _dataBuffer.add(dataPoint);
    }

    // Emit current data for UI
    _currentDataController.add({
      'altitude': _lastPosition!.altitude,
      'speed': _lastPosition!.speed,
      'gForce': gForce,
      'heading': _lastHeading,
      'presure': _lastPresure,
      'gpsAccuracy': _lastPosition!.accuracy,
      'hasGoodFix': _hasGoodGpsFix,
    });

    // Save buffer if full
    if (_dataBuffer.length >= _bufferSize) {
      _saveBufferedData();
    }
  }

  Future<void> _saveBufferedData() async {
    if (_dataBuffer.isEmpty) return;

    try {
      await DatabaseService.instance.insertSensorDataBatch(
        List.from(_dataBuffer),
      );
      _dataBuffer.clear();
    } catch (e) {
      print('Error saving buffered data: $e');
    }
  }

  double _calculateGForce(double x, double y, double z) {
    // Calculate magnitude of acceleration vector
    final magnitude = sqrt(x * x + y * y + z * z);
    // Convert to G-force (divide by standard gravity)
    return magnitude / 9.81;
  }

  Future<bool> _checkPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  void dispose() {
    _currentDataController.close();
    _stopListening();
  }
}
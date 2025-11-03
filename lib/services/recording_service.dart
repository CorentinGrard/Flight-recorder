import 'dart:async';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
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

  Position? _lastPosition;
  AccelerometerEvent? _lastAccelerometer;
  double? _lastHeading;

  final List<SensorDataPoint> _dataBuffer = [];
  Timer? _bufferTimer;
  static const int _bufferSize = 10; // Save every 10 points
  static const Duration _bufferInterval = Duration(seconds: 5);

  // Current values for UI
  final StreamController<Map<String, dynamic>> _currentDataController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get currentDataStream =>
      _currentDataController.stream;

  bool get isRecording => _isRecording;
  Flight? get currentFlight => _currentFlight;

  Future<bool> startRecording() async {
    if (_isRecording) return false;

    // Check and request permissions
    bool hasPermission = await _checkPermissions();
    if (!hasPermission) {
      throw Exception('Location permissions not granted');
    }

    // Create new flight
    final flight = Flight(
      startTime: DateTime.now(),
    );

    final flightId = await DatabaseService.instance.createFlight(flight);
    _currentFlightId = flightId;
    _currentFlight = flight.copyWith(id: flightId);

    _isRecording = true;
    _startListening();

    return true;
  }

  Future<Flight?> stopRecording() async {
    if (!_isRecording || _currentFlightId == null) return null;

    _isRecording = false;
    _stopListening();

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
    // GPS tracking (1 Hz)
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
      timeLimit: Duration(seconds: 1),
    );

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(_onPositionUpdate);

    // Accelerometer (50 Hz, will be sampled down)
    _accelerometerSubscription = accelerometerEventStream(
      samplingPeriod: Duration(milliseconds: 50),
    ).listen(_onAccelerometerUpdate);

    // Magnetometer for heading (10 Hz)
    _magnetometerSubscription = magnetometerEventStream(
      samplingPeriod: Duration(seconds: 1),
    ).listen(_onMagnetometerUpdate);

    // Start buffer timer
    _bufferTimer = Timer.periodic(_bufferInterval, (_) => _saveBufferedData());
  }

  void _stopListening() {
    _positionSubscription?.cancel();
    _accelerometerSubscription?.cancel();
    _magnetometerSubscription?.cancel();
    _bufferTimer?.cancel();

    _positionSubscription = null;
    _accelerometerSubscription = null;
    _magnetometerSubscription = null;
    _bufferTimer = null;
  }

  void _onPositionUpdate(Position position) {
    _lastPosition = position;
    _collectDataPoint();
  }

  void _onAccelerometerUpdate(AccelerometerEvent event) {
    _lastAccelerometer = event;
  }

  void _onMagnetometerUpdate(MagnetometerEvent event) {
    // Simple heading calculation (more accurate would use rotation matrix)
    _lastHeading = atan2(event.y, event.x) * (180 / pi);
    if (_lastHeading! < 0) _lastHeading = _lastHeading! + 360;
  }

  void _collectDataPoint() {
    if (!_isRecording || _currentFlightId == null || _lastPosition == null) {
      return;
    }

    final gForce = _lastAccelerometer != null
        ? _calculateGForce(
            _lastAccelerometer!.x,
            _lastAccelerometer!.y,
            _lastAccelerometer!.z,
          )
        : null;

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
    );

    _dataBuffer.add(dataPoint);

    // Emit current data for UI
    _currentDataController.add({
      'altitude': _lastPosition!.altitude,
      'speed': _lastPosition!.speed,
      'gForce': gForce,
      'heading': _lastHeading,
      'dataPointCount': _dataBuffer.length,
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
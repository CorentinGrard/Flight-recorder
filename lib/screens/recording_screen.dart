import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/recording_service.dart';
import 'flight_detail_screen.dart';

class RecordingScreen extends StatefulWidget {
  const RecordingScreen({super.key});

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {
  final _recordingService = RecordingService.instance;
  StreamSubscription? _dataSubscription;
  Timer? _durationTimer;
  
  Duration _elapsedTime = Duration.zero;
  double? _currentAltitude;
  double? _currentSpeed;
  double? _currentGForce;
  double? _currentHeading;
  int _dataPointCount = 0;

  @override
  void initState() {
    super.initState();
    _startListening();
    _startDurationTimer();
  }

  @override
  void dispose() {
    _dataSubscription?.cancel();
    _durationTimer?.cancel();
    super.dispose();
  }

  void _startListening() {
    _dataSubscription = _recordingService.currentDataStream.listen((data) {
      if (mounted) {
        setState(() {
          _currentAltitude = data['altitude'];
          _currentSpeed = data['speed'];
          _currentGForce = data['gForce'];
          _currentHeading = data['heading'];
          _dataPointCount = data['dataPointCount'] ?? 0;
        });
      }
    });
  }

  void _startDurationTimer() {
    final startTime = _recordingService.currentFlight?.startTime ?? DateTime.now();
    
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _elapsedTime = DateTime.now().difference(startTime);
        });
      }
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$hours:$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Prevent accidental back navigation
        final shouldStop = await _showStopConfirmation();
        if (shouldStop == true) {
          await _stopRecording();
          return true;
        }
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Recording Flight'),
          centerTitle: true,
          automaticallyImplyLeading: false,
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
        ),
        body: SafeArea(
          child: Column(
            children: [
              // Duration display
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                color: Colors.red.shade50,
                child: Column(
                  children: [
                    Text(
                      _formatDuration(_elapsedTime),
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Recording in progress',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),

              // Current data display
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildDataCard(
                        'Altitude',
                        _currentAltitude != null
                            ? '${_currentAltitude!.toStringAsFixed(1)} m'
                            : '---',
                        Icons.terrain,
                        Colors.blue,
                      ),
                      const SizedBox(height: 12),
                      _buildDataCard(
                        'Speed',
                        _currentSpeed != null
                            ? '${(_currentSpeed! * 3.6).toStringAsFixed(1)} km/h'
                            : '---',
                        Icons.speed,
                        Colors.green,
                      ),
                      const SizedBox(height: 12),
                      _buildDataCard(
                        'G-Force',
                        _currentGForce != null
                            ? '${_currentGForce!.toStringAsFixed(2)} G'
                            : '---',
                        Icons.trending_up,
                        _getGForceColor(_currentGForce),
                      ),
                      const SizedBox(height: 12),
                      _buildDataCard(
                        'Heading',
                        _currentHeading != null
                            ? '${_currentHeading!.toStringAsFixed(0)}°'
                            : '---',
                        Icons.explore,
                        Colors.orange,
                      ),
                      const SizedBox(height: 12),
                      _buildDataCard(
                        'Data Points',
                        '$_dataPointCount',
                        Icons.data_usage,
                        Colors.purple,
                      ),
                    ],
                  ),
                ),
              ),

              // Stop button
              Padding(
                padding: const EdgeInsets.all(24),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _stopRecording(),
                    icon: const Icon(Icons.stop, size: 32),
                    label: const Text(
                      'Stop Recording',
                      style: TextStyle(fontSize: 20),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDataCard(String label, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getGForceColor(double? gForce) {
    if (gForce == null) return Colors.grey;
    if (gForce > 3.0) return Colors.red;
    if (gForce > 2.0) return Colors.orange;
    if (gForce < 0.5) return Colors.red;
    return Colors.green;
  }

  Future<bool?> _showStopConfirmation() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop Recording?'),
        content: const Text('Are you sure you want to stop recording this flight?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Stop', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _stopRecording() async {
    try {
      final flight = await _recordingService.stopRecording();
      
      if (flight != null && mounted) {
        // Navigate to flight detail screen
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => FlightDetailScreen(flightId: flight.id!),
          ),
        );
      } else if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error stopping recording: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
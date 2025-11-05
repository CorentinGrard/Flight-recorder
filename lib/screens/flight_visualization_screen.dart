import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:math' as math;
import '../models/flight_models.dart';
import '../services/database_service.dart';

enum VisualizationMode { speed, gForce }
enum ViewMode { map2D, profile }

class FlightVisualizationScreen extends StatefulWidget {
  final int flightId;

  const FlightVisualizationScreen({super.key, required this.flightId});

  @override
  State<FlightVisualizationScreen> createState() =>
      _FlightVisualizationScreenState();
}

class _FlightVisualizationScreenState extends State<FlightVisualizationScreen> {
  Flight? _flight;
  List<SensorDataPoint> _dataPoints = [];
  bool _isLoading = true;
  VisualizationMode _vizMode = VisualizationMode.speed;
  ViewMode _viewMode = ViewMode.map2D;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _loadFlightData();
  }

  Future<void> _loadFlightData() async {
    setState(() => _isLoading = true);

    try {
      final flight = await DatabaseService.instance.getFlight(widget.flightId);
      final dataPoints =
          await DatabaseService.instance.getSensorDataForFlight(widget.flightId);

      if (mounted) {
        setState(() {
          _flight = flight;
          _dataPoints = dataPoints;
          _isLoading = false;
        });

        // Center map on flight path
        if (_dataPoints.isNotEmpty) {
          _centerMapOnFlight();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading flight data: $e')),
        );
      }
    }
  }

  void _centerMapOnFlight() {
    if (_dataPoints.isEmpty) return;

    double minLat = _dataPoints.first.latitude;
    double maxLat = _dataPoints.first.latitude;
    double minLon = _dataPoints.first.longitude;
    double maxLon = _dataPoints.first.longitude;

    for (var point in _dataPoints) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLon) minLon = point.longitude;
      if (point.longitude > maxLon) maxLon = point.longitude;
    }

    final centerLat = (minLat + maxLat) / 2;
    final centerLon = (minLon + maxLon) / 2;

    // Calculate appropriate zoom level
    final latDiff = maxLat - minLat;
    final lonDiff = maxLon - minLon;
    final maxDiff = math.max(latDiff, lonDiff);

    double zoom = 13.0;
    if (maxDiff > 0.1) {
      zoom = 11.0;
    } else if (maxDiff > 0.05) {
      zoom = 12.0;
    } else if (maxDiff < 0.01) {
      zoom = 15.0;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapController.move(LatLng(centerLat, centerLon), zoom);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_flight?.name ?? 'Flight Visualization'),
        actions: [
          SegmentedButton<ViewMode>(
            segments: const [
              ButtonSegment(
                value: ViewMode.map2D,
                icon: Icon(Icons.map, size: 18),
              ),
              ButtonSegment(
                value: ViewMode.profile,
                icon: Icon(Icons.show_chart, size: 18),
              ),
            ],
            selected: {_viewMode},
            onSelectionChanged: (Set<ViewMode> selection) {
              setState(() {
                _viewMode = selection.first;
              });
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _dataPoints.isEmpty
              ? const Center(child: Text('No flight data available'))
              : Column(
                  children: [
                    // Mode toggle
                    Container(
                      padding: const EdgeInsets.all(8),
                      color: Theme.of(context).colorScheme.surfaceVariant,
                      child: Row(
                        children: [
                          const Text('Color by: '),
                          const SizedBox(width: 8),
                          SegmentedButton<VisualizationMode>(
                            segments: const [
                              ButtonSegment(
                                value: VisualizationMode.speed,
                                label: Text('Speed'),
                                icon: Icon(Icons.speed, size: 16),
                              ),
                              ButtonSegment(
                                value: VisualizationMode.gForce,
                                label: Text('G-Force'),
                                icon: Icon(Icons.trending_up, size: 16),
                              ),
                            ],
                            selected: {_vizMode},
                            onSelectionChanged: (Set<VisualizationMode> selection) {
                              setState(() {
                                _vizMode = selection.first;
                              });
                            },
                          ),
                          const Spacer(),
                          _buildLegend(),
                        ],
                      ),
                    ),
                    // Visualization
                    Expanded(
                      child: _viewMode == ViewMode.map2D
                          ? _build2DMap()
                          : _buildAltitudeProfile(),
                    ),
                  ],
                ),
    );
  }

  Widget _build2DMap() {
    if (_dataPoints.isEmpty) return const SizedBox();

    // Create polyline segments with colors
    final List<Polyline> polylines = [];
    
    for (int i = 0; i < _dataPoints.length - 1; i++) {
      final point1 = _dataPoints[i];
      final point2 = _dataPoints[i + 1];
      
      final color = _getColorForPoint(point1);
      
      polylines.add(
        Polyline(
          points: [
            LatLng(point1.latitude, point1.longitude),
            LatLng(point2.latitude, point2.longitude),
          ],
          color: color,
          strokeWidth: 4.0,
        ),
      );
    }

    // Add start and end markers
    final markers = [
      Marker(
        point: LatLng(_dataPoints.first.latitude, _dataPoints.first.longitude),
        width: 40,
        height: 40,
        child: const Icon(
          Icons.flight_takeoff,
          color: Colors.green,
          size: 30,
        ),
      ),
      Marker(
        point: LatLng(_dataPoints.last.latitude, _dataPoints.last.longitude),
        width: 40,
        height: 40,
        child: const Icon(
          Icons.flight_land,
          color: Colors.red,
          size: 30,
        ),
      ),
    ];

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: LatLng(
          _dataPoints.first.latitude,
          _dataPoints.first.longitude,
        ),
        initialZoom: 13.0,
        minZoom: 5.0,
        maxZoom: 18.0,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'app.corentin.planeur_tracker',
          maxZoom: 19,
        ),
        PolylineLayer(polylines: polylines),
        MarkerLayer(markers: markers),
      ],
    );
  }

  Widget _buildAltitudeProfile() {
    if (_dataPoints.isEmpty) return const SizedBox();

    // Find min/max altitude
    double minAlt = _dataPoints
        .where((p) => p.altitude != null)
        .map((p) => p.altitude!)
        .reduce(math.min);
    double maxAlt = _dataPoints
        .where((p) => p.altitude != null)
        .map((p) => p.altitude!)
        .reduce(math.max);

    final altRange = maxAlt - minAlt;
    if (altRange == 0) return const Center(child: Text('No altitude variation'));

    return CustomPaint(
      painter: AltitudeProfilePainter(
        dataPoints: _dataPoints,
        minAlt: minAlt,
        maxAlt: maxAlt,
        vizMode: _vizMode,
        getColor: _getColorForPoint,
      ),
      child: Container(),
    );
  }

  Color _getColorForPoint(SensorDataPoint point) {
    if (_vizMode == VisualizationMode.speed) {
      return _getColorForSpeed(point.speed);
    } else {
      return _getColorForGForce(point.gForce);
    }
  }

  Color _getColorForSpeed(double? speed) {
    if (speed == null) return Colors.grey;

    final speedKmh = speed * 3.6;

    // Color gradient: blue (slow) -> green -> yellow -> red (fast)
    if (speedKmh < 20) {
      return Colors.blue;
    } else if (speedKmh < 40) {
      return Colors.cyan;
    } else if (speedKmh < 60) {
      return Colors.green;
    } else if (speedKmh < 80) {
      return Colors.yellow;
    } else if (speedKmh < 100) {
      return Colors.orange;
    } else {
      return Colors.red;
    }
  }

  Color _getColorForGForce(double? gForce) {
    if (gForce == null) return Colors.grey;

    // Color gradient based on G-force
    if (gForce < 0.5) {
      return Colors.purple; // Negative G / freefall
    } else if (gForce < 1.0) {
      return Colors.blue;
    } else if (gForce < 1.5) {
      return Colors.green;
    } else if (gForce < 2.0) {
      return Colors.yellow;
    } else if (gForce < 3.0) {
      return Colors.orange;
    } else {
      return Colors.red; // High G
    }
  }

  Widget _buildLegend() {
    final labels = _vizMode == VisualizationMode.speed
        ? ['0', '40', '80', '120+ km/h']
        : ['<0.5', '1.0', '2.0', '3.0+ G'];

    final colors = _vizMode == VisualizationMode.speed
        ? [Colors.blue, Colors.green, Colors.orange, Colors.red]
        : [Colors.purple, Colors.green, Colors.orange, Colors.red];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < colors.length; i++) ...[
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: colors[i],
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            labels[i],
            style: const TextStyle(fontSize: 10),
          ),
          if (i < colors.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class AltitudeProfilePainter extends CustomPainter {
  final List<SensorDataPoint> dataPoints;
  final double minAlt;
  final double maxAlt;
  final VisualizationMode vizMode;
  final Color Function(SensorDataPoint) getColor;

  AltitudeProfilePainter({
    required this.dataPoints,
    required this.minAlt,
    required this.maxAlt,
    required this.vizMode,
    required this.getColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (dataPoints.isEmpty) return;

    final altRange = maxAlt - minAlt;
    final padding = 40.0;
    final graphWidth = size.width - 2 * padding;
    final graphHeight = size.height - 2 * padding;

    // Draw axes
    final axisPaint = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = 2;

    // Y-axis
    canvas.drawLine(
      Offset(padding, padding),
      Offset(padding, size.height - padding),
      axisPaint,
    );

    // X-axis
    canvas.drawLine(
      Offset(padding, size.height - padding),
      Offset(size.width - padding, size.height - padding),
      axisPaint,
    );

    // Draw grid lines
    final gridPaint = Paint()
      ..color = Colors.grey.shade300
      ..strokeWidth = 1;

    for (int i = 0; i <= 4; i++) {
      final y = padding + (graphHeight * i / 4);
      canvas.drawLine(
        Offset(padding, y),
        Offset(size.width - padding, y),
        gridPaint,
      );
    }

    // Draw altitude labels
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    for (int i = 0; i <= 4; i++) {
      final alt = maxAlt - (altRange * i / 4);
      final y = padding + (graphHeight * i / 4);

      textPainter.text = TextSpan(
        text: '${alt.toStringAsFixed(0)}m',
        style: const TextStyle(color: Colors.black, fontSize: 12),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(5, y - 6));
    }

    // Draw profile with colored segments
    for (int i = 0; i < dataPoints.length - 1; i++) {
      final point1 = dataPoints[i];
      final point2 = dataPoints[i + 1];

      if (point1.altitude == null || point2.altitude == null) continue;

      final x1 = padding + (graphWidth * i / dataPoints.length);
      final x2 = padding + (graphWidth * (i + 1) / dataPoints.length);

      final y1 = size.height -
          padding -
          ((point1.altitude! - minAlt) / altRange * graphHeight);
      final y2 = size.height -
          padding -
          ((point2.altitude! - minAlt) / altRange * graphHeight);

      final segmentPaint = Paint()
        ..color = getColor(point1)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), segmentPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
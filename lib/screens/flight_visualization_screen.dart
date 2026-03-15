import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../models/flight_models.dart';
import '../services/database_service.dart';
import '../widgets/flight_3d_map_view.dart';

enum VisualizationMode { speed, gForce }
enum ViewMode { map, profile }

class FlightVisualizationScreen extends StatefulWidget {
  final int flightId;

  const FlightVisualizationScreen({super.key, required this.flightId});

  @override
  State<FlightVisualizationScreen> createState() =>
      _FlightVisualizationScreenState();
}

class _FlightVisualizationScreenState
    extends State<FlightVisualizationScreen> {
  Flight? _flight;
  List<SensorDataPoint> _dataPoints = [];
  bool _isLoading = true;
  VisualizationMode _vizMode = VisualizationMode.speed;
  ViewMode _viewMode = ViewMode.map;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_flight?.name ?? 'Flight Visualization'),
        actions: [
          SegmentedButton<ViewMode>(
            segments: const [
              ButtonSegment(
                value: ViewMode.map,
                icon: Icon(Icons.map, size: 18),
                label: Text('Map'),
              ),
              ButtonSegment(
                value: ViewMode.profile,
                icon: Icon(Icons.show_chart, size: 18),
                label: Text('Profile'),
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
                    // Color-mode selector + legend
                    Container(
                      padding: const EdgeInsets.all(8),
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
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
                              onSelectionChanged:
                                  (Set<VisualizationMode> selection) {
                                setState(() {
                                  _vizMode = selection.first;
                                });
                              },
                            ),
                            const SizedBox(width: 16),
                            _buildLegend(),
                          ],
                        ),
                      ),
                    ),

                    // Main content
                    Expanded(
                      child: _viewMode == ViewMode.map
                          ? Flight3DMapView(
                              dataPoints: _dataPoints,
                              getColor: _getColorForPoint,
                            )
                          : _buildAltitudeProfile(),
                    ),
                  ],
                ),
    );
  }

  // ── Altitude profile ────────────────────────────────────────────────────────

  Widget _buildAltitudeProfile() {
    if (_dataPoints.isEmpty) return const SizedBox();

    double minAlt = _dataPoints
        .where((p) => p.altitude != null)
        .map((p) => p.altitude!)
        .reduce(math.min);
    double maxAlt = _dataPoints
        .where((p) => p.altitude != null)
        .map((p) => p.altitude!)
        .reduce(math.max);

    final altRange = maxAlt - minAlt;
    if (altRange == 0) {
      return const Center(child: Text('No altitude variation'));
    }

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

  // ── Color helpers ───────────────────────────────────────────────────────────

  Color _getColorForPoint(SensorDataPoint point) {
    if (_vizMode == VisualizationMode.speed) {
      return _getColorForSpeed(point.speed);
    } else {
      return _getColorForGForce(point.gForce);
    }
  }

  Color _lerpColor(Color a, Color b, double t) {
    t = t.clamp(0.0, 1.0);
    return Color.lerp(a, b, t)!;
  }

  Color _getColorForSpeed(double? speed) {
    if (speed == null) return Colors.grey;
    final speedKmh = speed * 3.6;
    const double slowKmh = 80.0;
    const double fastKmh = 150.0;
    if (speedKmh <= slowKmh) return Colors.green;
    if (speedKmh >= fastKmh) return Colors.red;
    final t = (speedKmh - slowKmh) / (fastKmh - slowKmh);
    return t < 0.5
        ? _lerpColor(Colors.green, Colors.yellow, t * 2)
        : _lerpColor(Colors.yellow, Colors.red, (t - 0.5) * 2);
  }

  Color _getColorForGForce(double? gForce) {
    if (gForce == null) return Colors.grey;
    const double normalG = 1.0;
    const double highG = 2.0;
    const double extremeG = 4.0;
    if (gForce <= normalG) return Colors.green;
    if (gForce >= extremeG) return Colors.red;
    if (gForce < highG) {
      return _lerpColor(Colors.green, Colors.yellow,
          (gForce - normalG) / (highG - normalG));
    } else {
      return _lerpColor(Colors.yellow, Colors.red,
          (gForce - highG) / (extremeG - highG));
    }
  }

  // ── Legend ──────────────────────────────────────────────────────────────────

  Widget _buildLegend() {
    final labels = _vizMode == VisualizationMode.speed
        ? ['80 km/h', '115 km/h', '150+ km/h']
        : ['1G', '2G', '4G+'];
    final colors = [Colors.green, Colors.yellow, Colors.red];

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
          Text(labels[i], style: const TextStyle(fontSize: 10)),
          if (i < colors.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Altitude profile painter (unchanged)
// ─────────────────────────────────────────────────────────────────────────────

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
    const padding = 40.0;
    final graphWidth = size.width - 2 * padding;
    final graphHeight = size.height - 2 * padding;

    final axisPaint = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = 2;

    canvas.drawLine(Offset(padding, padding),
        Offset(padding, size.height - padding), axisPaint);
    canvas.drawLine(Offset(padding, size.height - padding),
        Offset(size.width - padding, size.height - padding), axisPaint);

    final gridPaint = Paint()
      ..color = Colors.grey.shade300
      ..strokeWidth = 1;

    for (int i = 0; i <= 4; i++) {
      final y = padding + (graphHeight * i / 4);
      canvas.drawLine(
          Offset(padding, y), Offset(size.width - padding, y), gridPaint);
    }

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

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

      canvas.drawLine(
        Offset(x1, y1),
        Offset(x2, y2),
        Paint()
          ..color = getColor(point1)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
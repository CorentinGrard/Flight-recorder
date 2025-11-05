import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:vector_math/vector_math_64.dart' as vm;
import '../models/flight_models.dart';

class Flight3DView extends StatefulWidget {
  final List<SensorDataPoint> dataPoints;
  final Color Function(SensorDataPoint) getColor;

  const Flight3DView({
    super.key,
    required this.dataPoints,
    required this.getColor,
  });

  @override
  State<Flight3DView> createState() => _Flight3DViewState();
}

class _Flight3DViewState extends State<Flight3DView> {
  double _rotationX = -0.5; // Tilt angle (looking down)
  double _rotationY = 0.0; // Rotation around vertical axis
  double _zoom = 1.0;
  Offset? _lastPanPosition;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (details) {
        _lastPanPosition = details.localPosition;
      },
      onPanUpdate: (details) {
        if (_lastPanPosition != null) {
          final delta = details.localPosition - _lastPanPosition!;
          setState(() {
            _rotationY += delta.dx * 0.01;
            _rotationX = (_rotationX - delta.dy * 0.01).clamp(-math.pi / 2, 0);
          });
          _lastPanPosition = details.localPosition;
        }
      },
      onPanEnd: (_) {
        _lastPanPosition = null;
      },
      child: Column(
        children: [
          // Controls
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.black87,
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.white, size: 16),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Drag to rotate',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  onPressed: () {
                    setState(() {
                      _rotationX = -0.5;
                      _rotationY = 0.0;
                      _zoom = 1.0;
                    });
                  },
                  tooltip: 'Reset view',
                ),
              ],
            ),
          ),
          // 3D View
          Expanded(
            child: Container(
              color: Colors.grey.shade900,
              child: CustomPaint(
                painter: Terrain3DPainter(
                  dataPoints: widget.dataPoints,
                  getColor: widget.getColor,
                  rotationX: _rotationX,
                  rotationY: _rotationY,
                  zoom: _zoom,
                ),
                child: Container(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class Terrain3DPainter extends CustomPainter {
  final List<SensorDataPoint> dataPoints;
  final Color Function(SensorDataPoint) getColor;
  final double rotationX;
  final double rotationY;
  final double zoom;

  Terrain3DPainter({
    required this.dataPoints,
    required this.getColor,
    required this.rotationX,
    required this.rotationY,
    required this.zoom,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (dataPoints.isEmpty) return;

    // Calculate bounds
    double minLat = dataPoints.first.latitude;
    double maxLat = dataPoints.first.latitude;
    double minLon = dataPoints.first.longitude;
    double maxLon = dataPoints.first.longitude;
    double minAlt = dataPoints.first.altitude ?? 0;
    double maxAlt = dataPoints.first.altitude ?? 0;

    for (var point in dataPoints) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLon) minLon = point.longitude;
      if (point.longitude > maxLon) maxLon = point.longitude;
      if (point.altitude != null) {
        if (point.altitude! < minAlt) minAlt = point.altitude!;
        if (point.altitude! > maxAlt) maxAlt = point.altitude!;
      }
    }

    final latRange = maxLat - minLat;
    final lonRange = maxLon - minLon;
    final altRange = maxAlt - minAlt;

    if (latRange == 0 || lonRange == 0) return;

    // Create terrain grid (simplified - just use flight path points)
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final scale = math.min(size.width, size.height) * 0.4 * zoom;

    // Create rotation matrices
    final rotX = vm.Matrix4.rotationX(rotationX);
    final rotY = vm.Matrix4.rotationY(rotationY);
    final rotation = rotY * rotX;

    // Project and draw terrain base (grid)
    _drawTerrainGrid(
      canvas,
      size,
      minLat,
      maxLat,
      minLon,
      maxLon,
      minAlt,
      latRange,
      lonRange,
      altRange,
      scale,
      rotation,
      centerX,
      centerY,
    );

    // Project and draw flight path with 3D effect
    final projectedPoints = <_Point3D>[];

    for (var point in dataPoints) {
      if (point.altitude == null) continue;

      // Normalize coordinates
      final x = ((point.longitude - minLon) / lonRange - 0.5) * scale;
      final y = -((point.altitude! - minAlt) / altRange) * scale * 0.5;
      final z = ((point.latitude - minLat) / latRange - 0.5) * scale;

      // Apply rotation
      final vec = vm.Vector3(x, y, z);
      final rotated = rotation.transform3(vec);

      // Project to 2D (simple orthographic projection)
      final screenX = centerX + rotated.x;
      final screenY = centerY + rotated.y;

      projectedPoints.add(_Point3D(
        screenX,
        screenY,
        rotated.z,
        getColor(point),
        point,
      ));
    }

    // Draw flight path segments FIRST (in original order, not depth sorted)
    for (int i = 0; i < projectedPoints.length - 1; i++) {
      final p1 = projectedPoints[i];
      final p2 = projectedPoints[i + 1];

      // Determine if segment should be visible based on average depth
      final avgDepth = (p1.depth + p2.depth) / 2;

      // Draw line segment
      final paint = Paint()
        ..color = p1.color.withOpacity(0.8)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(
        Offset(p1.x, p1.y),
        Offset(p2.x, p2.y),
        paint,
      );
    }

    // Then draw points on top (sorted by depth for proper occlusion)
    projectedPoints.sort((a, b) => b.depth.compareTo(a.depth));

    // Draw points on path
    for (var point in projectedPoints) {
      final paint = Paint()
        ..color = point.color
        ..style = PaintingStyle.fill;

      canvas.drawCircle(
        Offset(point.x, point.y),
        2.5,
        paint,
      );
    }

    // Draw start and end markers (get first and last from unsorted list)
    if (dataPoints.isNotEmpty) {
      final firstPoint = projectedPoints.firstWhere(
        (p) => p.dataPoint == dataPoints.first,
      );
      final lastPoint = projectedPoints.firstWhere(
        (p) => p.dataPoint == dataPoints.last,
      );
      
      _drawMarker(canvas, firstPoint, '🛫', Colors.green);
      _drawMarker(canvas, lastPoint, '🛬', Colors.red);
    }

    // Draw axes labels
    _drawAxes(canvas, size, centerX, centerY);
  }

  void _drawTerrainGrid(
    Canvas canvas,
    Size size,
    double minLat,
    double maxLat,
    double minLon,
    double maxLon,
    double minAlt,
    double latRange,
    double lonRange,
    double altRange,
    double scale,
    vm.Matrix4 rotation,
    double centerX,
    double centerY,
  ) {
    final gridPaint = Paint()
      ..color = Colors.grey.shade700
      ..strokeWidth = 1;

    // Draw grid lines (simplified terrain)
    const gridSize = 10;

    for (int i = 0; i <= gridSize; i++) {
      final latFrac = i / gridSize;
      
      // Latitude lines
      final linePoints = <Offset>[];
      for (int j = 0; j <= gridSize; j++) {
        final lonFrac = j / gridSize;
        
        final x = (lonFrac - 0.5) * scale;
        final y = 0.0; // Ground level
        final z = (latFrac - 0.5) * scale;

        final vec = vm.Vector3(x, y, z);
        final rotated = rotation.transform3(vec);

        linePoints.add(Offset(centerX + rotated.x, centerY + rotated.y));
      }

      for (int j = 0; j < linePoints.length - 1; j++) {
        canvas.drawLine(linePoints[j], linePoints[j + 1], gridPaint);
      }
    }

    for (int j = 0; j <= gridSize; j++) {
      final lonFrac = j / gridSize;
      
      // Longitude lines
      final linePoints = <Offset>[];
      for (int i = 0; i <= gridSize; i++) {
        final latFrac = i / gridSize;
        
        final x = (lonFrac - 0.5) * scale;
        final y = 0.0; // Ground level
        final z = (latFrac - 0.5) * scale;

        final vec = vm.Vector3(x, y, z);
        final rotated = rotation.transform3(vec);

        linePoints.add(Offset(centerX + rotated.x, centerY + rotated.y));
      }

      for (int i = 0; i < linePoints.length - 1; i++) {
        canvas.drawLine(linePoints[i], linePoints[i + 1], gridPaint);
      }
    }
  }

  void _drawMarker(Canvas canvas, _Point3D point, String emoji, Color color) {
    // Draw background circle
    final bgPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(point.x, point.y), 15, bgPaint);

    // Draw emoji text
    final textPainter = TextPainter(
      text: TextSpan(
        text: emoji,
        style: const TextStyle(fontSize: 16),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(point.x - textPainter.width / 2, point.y - textPainter.height / 2),
    );

    // Draw altitude label
    if (point.dataPoint.altitude != null) {
      final altText = TextPainter(
        text: TextSpan(
          text: '${point.dataPoint.altitude!.toStringAsFixed(0)}m',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(color: Colors.black, blurRadius: 2),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      altText.layout();
      altText.paint(
        canvas,
        Offset(point.x - altText.width / 2, point.y + 20),
      );
    }
  }

  void _drawAxes(Canvas canvas, Size size, double centerX, double centerY) {
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    // Draw axis labels
    final labels = [
      ('N ↑', Offset(centerX, 20)),
      ('W ←', Offset(20, centerY)),
      ('E →', Offset(size.width - 40, centerY)),
      ('S ↓', Offset(centerX, size.height - 20)),
    ];

    for (var label in labels) {
      textPainter.text = TextSpan(
        text: label.$1,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          label.$2.dx - textPainter.width / 2,
          label.$2.dy - textPainter.height / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _Point3D {
  final double x;
  final double y;
  final double depth;
  final Color color;
  final SensorDataPoint dataPoint;

  _Point3D(this.x, this.y, this.depth, this.color, this.dataPoint);
}
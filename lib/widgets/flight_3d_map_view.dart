import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:math' as math;
import '../models/flight_models.dart';

/// A unified view that merges the 2D map and 3D flight path.
///
/// At tilt = 0  →  looks exactly like a flat 2D map (flutter_map tiles visible).
/// Dragging up  →  tilts into perspective 3D.
/// The tilt is clamped so you can never go "under" the ground plane.
/// Pinch-to-zoom and pan work at all tilt angles.
class Flight3DMapView extends StatefulWidget {
  final List<SensorDataPoint> dataPoints;
  final Color Function(SensorDataPoint) getColor;

  const Flight3DMapView({
    super.key,
    required this.dataPoints,
    required this.getColor,
  });

  @override
  State<Flight3DMapView> createState() => _Flight3DMapViewState();
}

class _Flight3DMapViewState extends State<Flight3DMapView> {
  final MapController _mapController = MapController();

  /// Tilt angle in radians. 0 = top-down (flat map). Clamped to [0, π/2).
  double _tiltAngle = 0.0;

  /// Zoom level forwarded to flutter_map.
  double _zoom = 13.0;

  Offset? _lastPanPosition;
  double? _lastScaleValue;

  // Computed bounds of the flight path
  late double _minLat, _maxLat, _minLon, _maxLon, _minAlt, _maxAlt;
  late LatLng _center;

  @override
  void initState() {
    super.initState();
    _computeBounds();
  }

  void _computeBounds() {
    if (widget.dataPoints.isEmpty) return;

    _minLat = widget.dataPoints.first.latitude;
    _maxLat = widget.dataPoints.first.latitude;
    _minLon = widget.dataPoints.first.longitude;
    _maxLon = widget.dataPoints.first.longitude;
    _minAlt = widget.dataPoints.first.altitude ?? 0;
    _maxAlt = widget.dataPoints.first.altitude ?? 0;

    for (var p in widget.dataPoints) {
      if (p.latitude < _minLat) _minLat = p.latitude;
      if (p.latitude > _maxLat) _maxLat = p.latitude;
      if (p.longitude < _minLon) _minLon = p.longitude;
      if (p.longitude > _maxLon) _maxLon = p.longitude;
      if (p.altitude != null) {
        if (p.altitude! < _minAlt) _minAlt = p.altitude!;
        if (p.altitude! > _maxAlt) _maxAlt = p.altitude!;
      }
    }

    _center = LatLng((_minLat + _maxLat) / 2, (_minLon + _maxLon) / 2);

    final maxDiff = math.max(_maxLat - _minLat, _maxLon - _minLon);
    if (maxDiff > 0.1) {
      _zoom = 11.0;
    } else if (maxDiff > 0.05) {
      _zoom = 12.0;
    } else if (maxDiff < 0.01) {
      _zoom = 15.0;
    } else {
      _zoom = 13.0;
    }
  }

  void _resetView() {
    setState(() => _tiltAngle = 0.0);
    _mapController.move(_center, _zoom);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onScaleStart: (details) {
        _lastScaleValue = 1.0;
        _lastPanPosition = details.localFocalPoint;
      },
      onScaleUpdate: (details) {
        setState(() {
          // ── Pinch → zoom ──
          if (details.pointerCount >= 2 && _lastScaleValue != null) {
            final delta = details.scale - _lastScaleValue!;
            _zoom = (_zoom + delta * 3).clamp(5.0, 18.0);
            _mapController.move(_mapController.camera.center, _zoom);
            _lastScaleValue = details.scale;
          }

          // ── Single-finger drag ──
          if (details.pointerCount == 1 && _lastPanPosition != null) {
            final delta = details.localFocalPoint - _lastPanPosition!;

            // Vertical drag → tilt (drag up = more tilt toward horizon)
            _tiltAngle =
                (_tiltAngle - delta.dy * 0.005).clamp(0.0, math.pi / 2 - 0.05);

            // Horizontal drag → pan the map (only when near-flat)
            // When tilted, horizontal moves the map center instead
            if (_tiltAngle < 0.1) {
              final camera = _mapController.camera;
              final newCenter = camera.offsetToCrs(
                Offset(
                  camera.nonRotatedSize.width / 2 - delta.dx,
                  camera.nonRotatedSize.height / 2 - delta.dy,
                ),
              );
              _mapController.move(newCenter, _zoom);
            }
          }

          _lastPanPosition = details.localFocalPoint;
        });
      },
      onScaleEnd: (_) {
        _lastPanPosition = null;
        _lastScaleValue = null;
      },
      child: Stack(
        children: [
          // ── Layer 1: real OSM map tiles ──
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: _zoom,
              minZoom: 5.0,
              maxZoom: 18.0,
              // Hand all interaction to our GestureDetector
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.none,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'app.corentin.planeur_tracker',
                maxZoom: 19,
              ),
            ],
          ),

          // ── Layer 2: 3D flight path overlay ──
          // We use a MapBuilder so the painter always gets a fresh MapCamera.
          MapFlutterMapBuilderLayer(
            builder: (context, _) {
              final camera = MapCamera.of(context);
              return IgnorePointer(
                child: CustomPaint(
                  painter: _FlightOverlayPainter(
                    dataPoints: widget.dataPoints,
                    getColor: widget.getColor,
                    tiltAngle: _tiltAngle,
                    minAlt: _minAlt,
                    maxAlt: _maxAlt,
                    camera: camera,
                  ),
                  child: const SizedBox.expand(),
                ),
              );
            },
          ),

          // ── Layer 3: UI controls ──
          Positioned(
            top: 8,
            right: 8,
            child: Column(
              children: [
                _ControlButton(
                  icon: Icons.center_focus_strong,
                  tooltip: 'Reset view',
                  onTap: _resetView,
                ),
                const SizedBox(height: 8),
                _ControlButton(
                  icon: Icons.add,
                  tooltip: 'Zoom in',
                  onTap: () => setState(() {
                    _zoom = (_zoom + 1).clamp(5.0, 18.0);
                    _mapController.move(_mapController.camera.center, _zoom);
                  }),
                ),
                const SizedBox(height: 4),
                _ControlButton(
                  icon: Icons.remove,
                  tooltip: 'Zoom out',
                  onTap: () => setState(() {
                    _zoom = (_zoom - 1).clamp(5.0, 18.0);
                    _mapController.move(_mapController.camera.center, _zoom);
                  }),
                ),
              ],
            ),
          ),

          // ── Layer 4: tilt hint ──
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Center(child: _TiltIndicator(tiltAngle: _tiltAngle)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper layer widget that exposes MapCamera inside a flutter_map Stack
// ─────────────────────────────────────────────────────────────────────────────

class MapFlutterMapBuilderLayer extends StatelessWidget {
  final Widget Function(BuildContext context, MapCamera camera) builder;

  const MapFlutterMapBuilderLayer({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return builder(context, camera);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CustomPainter — draws the 3D flight path over the live map tiles
// ─────────────────────────────────────────────────────────────────────────────

class _FlightOverlayPainter extends CustomPainter {
  final List<SensorDataPoint> dataPoints;
  final Color Function(SensorDataPoint) getColor;
  final double tiltAngle;
  final double minAlt, maxAlt;
  final MapCamera camera;

  _FlightOverlayPainter({
    required this.dataPoints,
    required this.getColor,
    required this.tiltAngle,
    required this.minAlt,
    required this.maxAlt,
    required this.camera,
  });

  /// Converts a lat/lon + altitude pixel-lift to a screen Offset.
  ///
  /// [altLiftPx] is how many pixels above the ground the point should appear.
  /// At tiltAngle = 0 there is no lift (everything lies flat on the map).
  Offset _project(double lat, double lon, double altLiftPx) {
    // Ground position in screen space (flutter_map v6 API)
    final ground = camera.latLngToScreenOffset(LatLng(lat, lon));

    if (tiltAngle < 0.001 || altLiftPx == 0) return ground;

    // Simple vertical perspective lift:
    // The further a point is from the screen bottom, the more it recedes.
    // We lift the rendered point upward by altLiftPx scaled by sin(tilt).
    final lift = altLiftPx * math.sin(tiltAngle);
    return Offset(ground.dx, ground.dy - lift);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (dataPoints.isEmpty) return;

    final altRange = (maxAlt - minAlt).clamp(1.0, double.infinity);

    // Maximum pixel lift at full tilt — scales with screen height
    final maxLiftPx = size.height * 0.3;

    // ── Vertical shadow lines (only when tilted) ──
    if (tiltAngle > 0.05) {
      final shadowPaint = Paint()
        ..color = Colors.black26
        ..strokeWidth = 1;

      for (var point in dataPoints) {
        if (point.altitude == null) continue;
        final liftPx =
            ((point.altitude! - minAlt) / altRange) * maxLiftPx;
        final ground = _project(point.latitude, point.longitude, 0);
        final air = _project(point.latitude, point.longitude, liftPx);
        canvas.drawLine(ground, air, shadowPaint);
      }
    }

    // ── Flight path segments ──
    for (int i = 0; i < dataPoints.length - 1; i++) {
      final p1 = dataPoints[i];
      final p2 = dataPoints[i + 1];
      if (p1.altitude == null || p2.altitude == null) continue;

      final lift1 = ((p1.altitude! - minAlt) / altRange) * maxLiftPx;
      final lift2 = ((p2.altitude! - minAlt) / altRange) * maxLiftPx;

      canvas.drawLine(
        _project(p1.latitude, p1.longitude, lift1),
        _project(p2.latitude, p2.longitude, lift2),
        Paint()
          ..color = getColor(p1)
          ..strokeWidth = 3.5
          ..strokeCap = StrokeCap.round,
      );
    }

    // ── Start / end markers ──
    _drawMarker(canvas, dataPoints.first, true, altRange, maxLiftPx);
    _drawMarker(canvas, dataPoints.last, false, altRange, maxLiftPx);
  }

  void _drawMarker(Canvas canvas, SensorDataPoint point, bool isStart,
      double altRange, double maxLiftPx) {
    final liftPx = point.altitude != null
        ? ((point.altitude! - minAlt) / altRange) * maxLiftPx
        : 0.0;
    final pos = _project(point.latitude, point.longitude, liftPx);
    final color = isStart ? Colors.green : Colors.red;

    canvas.drawCircle(pos, 10, Paint()..color = color);
    canvas.drawCircle(
      pos,
      10,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _FlightOverlayPainter old) =>
      old.tiltAngle != tiltAngle ||
      old.camera != camera ||
      old.dataPoints != dataPoints;
}

// ─────────────────────────────────────────────────────────────────────────────
// Small helper widgets
// ─────────────────────────────────────────────────────────────────────────────

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
            ],
          ),
          child: Icon(icon, size: 20, color: Colors.black87),
        ),
      ),
    );
  }
}

class _TiltIndicator extends StatelessWidget {
  final double tiltAngle;
  const _TiltIndicator({required this.tiltAngle});

  @override
  Widget build(BuildContext context) {
    final pct = (tiltAngle / (math.pi / 2) * 100).round();
    final label = pct == 0
        ? 'Drag up to tilt into 3D'
        : 'Tilt $pct%  •  pinch to zoom';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label,
          style: const TextStyle(color: Colors.white, fontSize: 11)),
    );
  }
}
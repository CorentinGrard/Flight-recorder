import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../models/flight_models.dart';
import 'database_service.dart';

class ExportService {
  static final ExportService instance = ExportService._init();
  ExportService._init();

  Future<String> exportFlightToCsv(int flightId) async {
    final flight = await DatabaseService.instance.getFlight(flightId);
    if (flight == null) throw Exception('Flight not found');

    final dataPoints = await DatabaseService.instance.getSensorDataForFlight(flightId);

    // Generate filename
    final dateFormat = DateFormat('yyyyMMdd_HHmmss');
    final filename = 'flight_${dateFormat.format(flight.startTime)}.csv';

    // Get temporary directory
    final directory = await getTemporaryDirectory();
    final path = '${directory.path}/$filename';

    // Write CSV file
    final file = File(path);
    final sink = file.openWrite();

    // Write header
    sink.writeln(SensorDataPoint.csvHeader());

    // Write data points
    for (var point in dataPoints) {
      sink.writeln(point.toCsvRow());
    }

    await sink.close();

    return path;
  }

  Future<void> shareFlightCsv(int flightId) async {
    try {
      final csvPath = await exportFlightToCsv(flightId);
      await Share.shareXFiles(
        [XFile(csvPath)],
        subject: 'Flight Data',
        text: 'Flight recording data from Flight Recorder',
      );
    } catch (e) {
      throw Exception('Failed to export flight: $e');
    }
  }

  Future<String> exportFlightToGpx(int flightId) async {
    final flight = await DatabaseService.instance.getFlight(flightId);
    if (flight == null) throw Exception('Flight not found');

    final dataPoints = await DatabaseService.instance.getSensorDataForFlight(flightId);

    // Generate filename
    final dateFormat = DateFormat('yyyyMMdd_HHmmss');
    final filename = 'flight_${dateFormat.format(flight.startTime)}.gpx';

    // Get temporary directory
    final directory = await getTemporaryDirectory();
    final path = '${directory.path}/$filename';

    // Create GPX content
    final gpxContent = _generateGpxContent(flight, dataPoints);

    // Write file
    final file = File(path);
    await file.writeAsString(gpxContent);

    return path;
  }

  String _generateGpxContent(Flight flight, List<SensorDataPoint> dataPoints) {
    final buffer = StringBuffer();
    final dateFormat = DateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'");

    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<gpx version="1.1" creator="Flight Recorder"');
    buffer.writeln('  xmlns="http://www.topografix.com/GPX/1/1"');
    buffer.writeln('  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"');
    buffer.writeln('  xmlns:accel="http://flightrecorder.com/accel/1.0"');
    buffer.writeln('  xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">');
    
    buffer.writeln('  <metadata>');
    buffer.writeln('    <name>Flight Recorder ${dateFormat.format(flight.startTime)}</name>');
    buffer.writeln('    <time>${dateFormat.format(flight.startTime)}</time>');
    buffer.writeln('  </metadata>');
    
    buffer.writeln('  <trk>');
    buffer.writeln('    <name>Flight Track</name>');
    buffer.writeln('    <trkseg>');

    for (var point in dataPoints) {
      buffer.writeln('      <trkpt lat="${point.latitude}" lon="${point.longitude}">');
      if (point.altitude != null) {
        buffer.writeln('        <ele>${point.altitude}</ele>');
      }
      buffer.writeln('        <time>${dateFormat.format(point.timestamp)}</time>');
      
      // Add extensions for acceleration data
      if (point.accelX != null || point.gForce != null) {
        buffer.writeln('        <extensions>');
        if (point.accelX != null) {
          buffer.writeln('          <accel:x>${point.accelX}</accel:x>');
        }
        if (point.accelY != null) {
          buffer.writeln('          <accel:y>${point.accelY}</accel:y>');
        }
        if (point.accelZ != null) {
          buffer.writeln('          <accel:z>${point.accelZ}</accel:z>');
        }
        if (point.gForce != null) {
          buffer.writeln('          <accel:gforce>${point.gForce}</accel:gforce>');
        }
        buffer.writeln('        </extensions>');
      }
      
      buffer.writeln('      </trkpt>');
    }

    buffer.writeln('    </trkseg>');
    buffer.writeln('  </trk>');
    buffer.writeln('</gpx>');

    return buffer.toString();
  }

  Future<void> shareFlightGpx(int flightId) async {
    try {
      final gpxPath = await exportFlightToGpx(flightId);
      await Share.shareXFiles(
        [XFile(gpxPath)],
        subject: 'Flight GPX',
        text: 'Flight track from Flight Recorder',
      );
    } catch (e) {
      throw Exception('Failed to export flight: $e');
    }
  }
} 
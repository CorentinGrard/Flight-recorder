import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/flight_models.dart';
import '../services/database_service.dart';
import '../services/export_service.dart';

class FlightDetailScreen extends StatefulWidget {
  final int flightId;

  const FlightDetailScreen({super.key, required this.flightId});

  @override
  State<FlightDetailScreen> createState() => _FlightDetailScreenState();
}

class _FlightDetailScreenState extends State<FlightDetailScreen> {
  Flight? _flight;
  int _dataPointCount = 0;
  bool _isLoading = true;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _loadFlight();
  }

  Future<void> _loadFlight() async {
    setState(() => _isLoading = true);

    try {
      final flight = await DatabaseService.instance.getFlight(widget.flightId);
      final count = await DatabaseService.instance.getSensorDataCount(widget.flightId);

      if (mounted) {
        setState(() {
          _flight = flight;
          _dataPointCount = count;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading flight: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flight Details'),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            onSelected: _handleMenuSelection,
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'export_csv',
                child: Row(
                  children: [
                    Icon(Icons.file_download),
                    SizedBox(width: 8),
                    Text('Export CSV'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'export_gpx',
                child: Row(
                  children: [
                    Icon(Icons.map),
                    SizedBox(width: 8),
                    Text('Export GPX'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Delete Flight', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _flight == null
              ? const Center(child: Text('Flight not found'))
              : _buildFlightDetails(),
    );
  }

  Widget _buildFlightDetails() {
    final dateFormat = DateFormat('EEEE, MMM dd, yyyy');
    final timeFormat = DateFormat('HH:mm:ss');

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date and Time
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_today,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                dateFormat.format(_flight!.startTime),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Started at ${timeFormat.format(_flight!.startTime)}',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 14,
                                ),
                              ),
                              if (_flight!.endTime != null)
                                Text(
                                  'Ended at ${timeFormat.format(_flight!.endTime!)}',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 14,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Stats Grid
            Text(
              'Flight Statistics',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            _buildStatsGrid(),
            const SizedBox(height: 24),

            // Data Info
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.data_usage,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Recorded Data Points',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$_dataPointCount points',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Export Buttons
            if (!_isExporting) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _exportFlight('csv'),
                  icon: const Icon(Icons.file_download),
                  label: const Text('Export as CSV'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _exportFlight('gpx'),
                  icon: const Icon(Icons.map),
                  label: const Text('Export as GPX'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                  ),
                ),
              ),
            ] else
              const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: [
        _buildStatCard(
          'Duration',
          _formatDuration(_flight!.duration),
          Icons.timer,
          Colors.blue,
        ),
        _buildStatCard(
          'Max Altitude',
          _flight!.maxAltitude != null
              ? '${_flight!.maxAltitude!.toStringAsFixed(0)} m'
              : 'N/A',
          Icons.terrain,
          Colors.green,
        ),
        _buildStatCard(
          'Distance',
          _flight!.totalDistance != null
              ? '${(_flight!.totalDistance! / 1000).toStringAsFixed(2)} km'
              : 'N/A',
          Icons.route,
          Colors.orange,
        ),
        _buildStatCard(
          'Max +G',
          _flight!.maxPositiveG != null
              ? '${_flight!.maxPositiveG!.toStringAsFixed(2)} G'
              : 'N/A',
          Icons.arrow_upward,
          Colors.red,
        ),
        _buildStatCard(
          'Max -G',
          _flight!.maxNegativeG != null
              ? '${_flight!.maxNegativeG!.toStringAsFixed(2)} G'
              : 'N/A',
          Icons.arrow_downward,
          Colors.purple,
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(int? seconds) {
    if (seconds == null) return 'N/A';

    final duration = Duration(seconds: seconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final secs = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m ${secs}s';
    }
    if (minutes > 0) {
      return '${minutes}m ${secs}s';
    }
    return '${secs}s';
  }

  Future<void> _handleMenuSelection(String value) async {
    switch (value) {
      case 'export_csv':
        await _exportFlight('csv');
        break;
      case 'export_gpx':
        await _exportFlight('gpx');
        break;
      case 'delete':
        await _confirmDelete();
        break;
    }
  }

  Future<void> _exportFlight(String format) async {
    setState(() => _isExporting = true);

    try {
      if (format == 'csv') {
        await ExportService.instance.shareFlightCsv(widget.flightId);
      } else if (format == 'gpx') {
        await ExportService.instance.shareFlightGpx(widget.flightId);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Export successful')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Flight'),
        content: const Text(
          'Are you sure you want to delete this flight? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _deleteFlight();
    }
  }

  Future<void> _deleteFlight() async {
    try {
      await DatabaseService.instance.deleteFlight(widget.flightId);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Flight deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting flight: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
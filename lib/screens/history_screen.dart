import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/flight_models.dart';
import '../services/database_service.dart';
import '../services/export_service.dart';
import 'flight_detail_screen.dart';
import 'flight_visualization_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Flight> _flights = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFlights();
  }

  Future<void> _loadFlights() async {
    setState(() => _isLoading = true);
    
    try {
      final flights = await DatabaseService.instance.getAllFlights();
      if (mounted) {
        setState(() {
          _flights = flights;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading flights: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flight History'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadFlights,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _flights.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadFlights,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _flights.length,
                    itemBuilder: (context, index) {
                      return _buildFlightCard(_flights[index]);
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.flight_outlined,
            size: 100,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            'No flights recorded yet',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.grey.shade600,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start recording to see your flights here',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildFlightCard(Flight flight) {
    final dateFormat = DateFormat('MMM dd, yyyy');
    final timeFormat = DateFormat('HH:mm');
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: InkWell(
        onTap: () => _openFlightDetail(flight.id!),
        onLongPress: () => _showFlightOptions(flight),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                flight.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: 14,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        dateFormat.format(flight.startTime),
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    timeFormat.format(flight.startTime),
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildStatChip(
                      Icons.timer,
                      _formatDuration(flight.duration),
                      Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildStatChip(
                      Icons.terrain,
                      flight.maxAltitude != null
                          ? '${flight.maxAltitude!.toStringAsFixed(0)}m'
                          : 'N/A',
                      Colors.green,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildStatChip(
                      Icons.route,
                      flight.totalDistance != null
                          ? '${(flight.totalDistance! / 1000).toStringAsFixed(1)}km'
                          : 'N/A',
                      Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildStatChip(
                      Icons.trending_up,
                      flight.maxPositiveG != null
                          ? '${flight.maxPositiveG!.toStringAsFixed(1)}G'
                          : 'N/A',
                      Colors.red,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatChip(IconData icon, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int? seconds) {
    if (seconds == null) return 'N/A';
    
    final duration = Duration(seconds: seconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  Future<void> _openFlightDetail(int flightId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FlightDetailScreen(flightId: flightId),
      ),
    );
    // Refresh list when returning
    _loadFlights();
  }

  Future<void> _showFlightOptions(Flight flight) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.visibility),
              title: const Text('View Details'),
              onTap: () => Navigator.of(context).pop('view'),
            ),
            ListTile(
              leading: const Icon(Icons.map),
              title: const Text('View Flight Path'),
              onTap: () => Navigator.of(context).pop('visualize'),
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Rename Flight'),
              onTap: () => Navigator.of(context).pop('rename'),
            ),
            ListTile(
              leading: const Icon(Icons.file_download),
              title: const Text('Export CSV'),
              onTap: () => Navigator.of(context).pop('export_csv'),
            ),
            ListTile(
              leading: const Icon(Icons.map),
              title: const Text('Export GPX'),
              onTap: () => Navigator.of(context).pop('export_gpx'),
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete Flight', style: TextStyle(color: Colors.red)),
              onTap: () => Navigator.of(context).pop('delete'),
            ),
          ],
        ),
      ),
    );

    if (action == null || !mounted) return;

    switch (action) {
      case 'view':
        _openFlightDetail(flight.id!);
        break;
      case 'visualize':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => FlightVisualizationScreen(flightId: flight.id!),
          ),
        );
        break;
      case 'rename':
        await _renameFlight(flight);
        break;
      case 'export_csv':
        await _exportFlight(flight.id!, 'csv');
        break;
      case 'export_gpx':
        await _exportFlight(flight.id!, 'gpx');
        break;
      case 'delete':
        await _deleteFlight(flight.id!);
        break;
    }
  }

  Future<void> _renameFlight(Flight flight) async {
    final controller = TextEditingController(text: flight.name);
    
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Flight'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Flight Name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != flight.name) {
      final updatedFlight = flight.copyWith(name: newName);
      await DatabaseService.instance.updateFlight(updatedFlight);
      _loadFlights();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Flight renamed')),
        );
      }
    }
  }

  Future<void> _exportFlight(int flightId, String format) async {
    try {
      if (format == 'csv') {
        await ExportService.instance.shareFlightCsv(flightId);
      } else if (format == 'gpx') {
        await ExportService.instance.shareFlightGpx(flightId);
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
    }
  }

  Future<void> _deleteFlight(int flightId) async {
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

    if (confirmed == true) {
      await DatabaseService.instance.deleteFlight(flightId);
      _loadFlights();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Flight deleted')),
        );
      }
    }
  }
}
import 'package:flutter/material.dart';
import '../services/recording_service.dart';
import 'recording_screen.dart';
import 'history_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  final _recordingService = RecordingService.instance;

  static const List<Widget> _pages = [
    RecordPage(),
    HistoryScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onItemTapped,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.flight),
            label: 'Record',
          ),
          NavigationDestination(
            icon: Icon(Icons.history),
            label: 'History',
          ),
        ],
      ),
    );
  }
}

class RecordPage extends StatelessWidget {
  const RecordPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Glider Tracker'),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.flight_takeoff,
              size: 120,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 40),
            Text(
              'Ready to fly',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            Text(
              'Tap the button below to start recording',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 60),
            ElevatedButton.icon(
              onPressed: () => _startRecording(context),
              icon: const Icon(Icons.fiber_manual_record, size: 32),
              label: const Text(
                'Start Recording',
                style: TextStyle(fontSize: 20),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 20,
                ),
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startRecording(BuildContext context) async {
    try {
      final success = await RecordingService.instance.startRecording();
      
      if (success && context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const RecordingScreen(),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
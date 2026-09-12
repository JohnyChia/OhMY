import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:record/record.dart';

class PermissionSettingsScreen extends StatefulWidget {
  const PermissionSettingsScreen({super.key});

  @override
  State<PermissionSettingsScreen> createState() =>
      _PermissionSettingsScreenState();
}

class _PermissionSettingsScreenState extends State<PermissionSettingsScreen>
    with WidgetsBindingObserver {
  bool loading = true;
  bool microphoneAllowed = false;
  LocationPermission locationPermission = LocationPermission.denied;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final recorder = AudioRecorder();
    try {
      final values = await Future.wait<Object>([
        recorder.hasPermission(),
        Geolocator.checkPermission(),
      ]);
      if (!mounted) return;
      setState(() {
        microphoneAllowed = values[0] as bool;
        locationPermission = values[1] as LocationPermission;
        loading = false;
      });
    } finally {
      await recorder.dispose();
    }
  }

  Future<void> _requestLocation() async {
    await Geolocator.requestPermission();
    await _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('App permissions')),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _PermissionTile(
                icon: Icons.mic_outlined,
                title: 'Microphone',
                subtitle: microphoneAllowed
                    ? 'Allowed for live voice and route commands'
                    : 'Not allowed',
                allowed: microphoneAllowed,
              ),
              const SizedBox(height: 12),
              _PermissionTile(
                icon: Icons.location_on_outlined,
                title: 'Location',
                subtitle:
                    locationPermission == LocationPermission.always ||
                        locationPermission == LocationPermission.whileInUse
                    ? 'Allowed for routes, weather and nearby places'
                    : 'Not allowed',
                allowed:
                    locationPermission == LocationPermission.always ||
                    locationPermission == LocationPermission.whileInUse,
              ),
              const SizedBox(height: 20),
              if (locationPermission == LocationPermission.denied)
                FilledButton.icon(
                  onPressed: _requestLocation,
                  icon: const Icon(Icons.location_on_outlined),
                  label: const Text('Request location permission'),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: Geolocator.openAppSettings,
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Open system permission settings'),
              ),
              const SizedBox(height: 12),
              const Text(
                'Android controls permission removal. Nova continues with reduced features when a permission is denied.',
                style: TextStyle(color: Color(0xFF596680), height: 1.4),
              ),
            ],
          ),
  );
}

class _PermissionTile extends StatelessWidget {
  const _PermissionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.allowed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool allowed;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Icon(
        allowed ? Icons.check_circle : Icons.error_outline,
        color: allowed ? Colors.green : Colors.orange,
      ),
    ),
  );
}

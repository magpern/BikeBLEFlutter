import 'package:flutter/material.dart';
import 'screens/ble_scan_screen.dart'; // ✅ Import the BLE scan screen
import 'services/update_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE Scanner',
      navigatorKey: navigatorKey, // Use the navigator key from update_service.dart
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true, // ✅ Use the latest Material Design 3 UI
      ),
      home: const AppWithUpdateCheck(), // Use the update check wrapper
    );
  }
}

// Widget wrapper to check for updates
class AppWithUpdateCheck extends StatefulWidget {
  const AppWithUpdateCheck({super.key});

  @override
  State<AppWithUpdateCheck> createState() => _AppWithUpdateCheckState();
}

class _AppWithUpdateCheckState extends State<AppWithUpdateCheck> {
  final UpdateService _updateService = UpdateService();
  bool _checkingForUpdates = false;

  @override
  void initState() {
    super.initState();
    // Check for updates after the first frame renders
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdates();
    });
  }

  Future<void> _checkForUpdates() async {
    if (_checkingForUpdates) return;
    
    setState(() {
      _checkingForUpdates = true;
    });
    
    try {
      final updateInfo = await _updateService.checkForUpdates(context);
      
      if (updateInfo['hasUpdate'] == true && mounted) {
        _updateService.showUpdateDialog(context, updateInfo);
      }
    } catch (e) {
      // Silently handle error - don't disturb the user if update check fails
    } finally {
      if (mounted) {
        setState(() {
          _checkingForUpdates = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show normal app UI
    return const BleScanScreen();
  }
}

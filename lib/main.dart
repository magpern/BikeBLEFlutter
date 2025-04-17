import 'package:flutter/material.dart';
import 'dart:io';
import 'screens/ble_scan_screen.dart'; // ✅ Import the BLE scan screen
import 'services/update_service.dart';
import 'package:open_file/open_file.dart';

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

class _AppWithUpdateCheckState extends State<AppWithUpdateCheck> with WidgetsBindingObserver {
  final UpdateService _updateService = UpdateService();
  bool _checkingForUpdates = false;
  File? _pendingApkInstall;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Check for updates after the first frame renders
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdates();
    });
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When app resumes, check if we need to continue APK installation
    if (state == AppLifecycleState.resumed && _pendingApkInstall != null) {
      // App has resumed after a permissions prompt, try to install again
      _tryInstallPendingApk();
    }
  }
  
  // Try to install APK after permissions were granted
  Future<void> _tryInstallPendingApk() async {
    if (_pendingApkInstall != null) {
      try {
        final apkFile = _pendingApkInstall!;
        _pendingApkInstall = null; // Clear pending install
        
        if (await apkFile.exists()) {
          final result = await OpenFile.open(apkFile.path);
          if (result.type != ResultType.done) {
            // Show manual install dialog if needed
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Please install the downloaded update manually"),
                  duration: Duration(seconds: 5),
                )
              );
            }
          }
        }
      } catch (e) {
        // Handle errors
        print("Error installing pending APK: $e");
      }
    }
  }

  Future<void> _checkForUpdates() async {
    if (_checkingForUpdates) return;
    
    setState(() {
      _checkingForUpdates = true;
    });
    
    try {
      final updateInfo = await _updateService.checkForUpdates(context);
      
      if (updateInfo['hasUpdate'] == true && mounted) {
        // Store download URL for the update service to access
        _updateService.setPendingUpdateCallback((file) {
          // This callback will be triggered when the APK is downloaded
          setState(() {
            _pendingApkInstall = file;
          });
        });
        
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

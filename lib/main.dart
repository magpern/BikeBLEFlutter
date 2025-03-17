import 'package:flutter/material.dart';
import 'screens/ble_scan_screen.dart'; // ✅ Import the BLE scan screen

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE Scanner',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true, // ✅ Use the latest Material Design 3 UI
      ),
      home: const BleScanScreen(), // ✅ Set BLE scan as the home screen
    );
  }
}

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:async';
import '../utils/ble_constants.dart';

class DfuProgressState {
  final double progress;
  final String state;
  final String? error;

  DfuProgressState({
    required this.progress,
    required this.state,
    this.error,
  });
}

class DfuService {
  static const String _dfuDeviceName = 'BikeUpdate';
  final _progressController = StreamController<DfuProgressState>.broadcast();
  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 1);

  /// Trigger DFU mode on the device
  Future<void> triggerDfuMode(BluetoothDevice device) async {
    int retryCount = 0;
    while (retryCount < _maxRetries) {
      try {
        print("📡 Triggering DFU mode... (Attempt ${retryCount + 1}/$_maxRetries)");
        
        // Ensure device is connected
        if (!device.isConnected) {
          print("🔌 Device not connected, attempting to connect...");
          await device.connect(timeout: const Duration(seconds: 5));
          await Future.delayed(const Duration(milliseconds: 500)); // Give it time to stabilize
        }

        // Get the custom service and characteristic
        final services = await device.discoverServices();
        final service = services.firstWhere(
          (s) => s.serviceUuid == BleConstants.customService,
          orElse: () => throw Exception('Custom service not found'),
        );
        
        final characteristic = service.characteristics.firstWhere(
          (c) => c.characteristicUuid == BleConstants.scanControlChar,
          orElse: () => throw Exception('Scan control characteristic not found'),
        );

        // Check if characteristic is writable
        if (!characteristic.properties.write) {
          throw Exception('Characteristic is not writable');
        }

        // Send DFU trigger command (0x05)
        await characteristic.write([0x05], withoutResponse: false);
        print("✅ DFU trigger command sent");

        // Wait a bit before disconnecting
        await Future.delayed(const Duration(milliseconds: 500));

        // Disconnect from the device
        await device.disconnect();
        print("✅ Disconnected from device");
        return; // Success, exit the retry loop
      } catch (e) {
        retryCount++;
        print("❌ Attempt $retryCount failed: $e");
        
        if (retryCount < _maxRetries) {
          print("⏳ Waiting before retry...");
          await Future.delayed(_retryDelay);
        } else {
          print("❌ All retry attempts failed");
          rethrow;
        }
      }
    }
  }

  /// Start DFU process
  Future<void> startDfu(String filePath, String? macAddress) async {
    try {
      print("📡 Starting DFU process...");
      
      // Simulate DFU process
      _simulateDfuProcess();
      
      print("✅ DFU process started");
    } catch (e) {
      print("❌ Failed to start DFU: $e");
      rethrow;
    }
  }

  /// Get DFU progress stream
  Stream<DfuProgressState> get progressStream => _progressController.stream;

  /// Cancel ongoing DFU process
  Future<void> cancelDfu() async {
    try {
      print("🛑 Cancelling DFU process...");
      _progressController.add(DfuProgressState(
        progress: 0,
        state: 'CANCELLED',
      ));
      print("✅ DFU process cancelled");
    } catch (e) {
      print("❌ Failed to cancel DFU: $e");
      rethrow;
    }
  }

  /// Simulate DFU process with progress updates
  Future<void> _simulateDfuProcess() async {
    final states = [
      'PREPARING',
      'UPLOADING',
      'VALIDATING',
      'COMPLETED'
    ];

    for (var i = 0; i <= 100; i += 10) {
      await Future.delayed(const Duration(milliseconds: 500));
      final state = states[(i ~/ 25).clamp(0, states.length - 1)];
      _progressController.add(DfuProgressState(
        progress: i / 100,
        state: state,
      ));
    }

    _progressController.add(DfuProgressState(
      progress: 1.0,
      state: 'COMPLETED',
    ));
  }
} 
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

  /// Trigger DFU mode on the device
  Future<void> triggerDfuMode(BluetoothDevice device) async {
    try {
      print("📡 Triggering DFU mode...");
      
      // Get the custom service and characteristic
      final services = await device.discoverServices();
      final service = services.firstWhere(
        (s) => s.serviceUuid == BleConstants.customService,
      );
      
      final characteristic = service.characteristics.firstWhere(
        (c) => c.characteristicUuid == BleConstants.scanControlChar,
      );

      // Send DFU trigger command (0x05)
      await characteristic.write([0x05], withoutResponse: false);
      print("✅ DFU trigger command sent");

      // Disconnect from the device
      await device.disconnect();
      print("✅ Disconnected from device");
    } catch (e) {
      print("❌ Failed to trigger DFU mode: $e");
      rethrow;
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
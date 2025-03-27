import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:nordic_dfu/nordic_dfu.dart';
import '../utils/ble_constants.dart';

class DfuService {
  static const String _dfuDeviceName = 'BikeUpdate';
  final NordicDfu _nordicDfu = NordicDfu();

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
      
      if (macAddress != null) {
        // On Android, use MAC address if available
        print("🔌 Using MAC address for DFU: $macAddress");
        await _nordicDfu.startDfu(
          macAddress,
          filePath,
          name: _dfuDeviceName,
        );
      } else {
        // On iOS or if MAC address is not available, scan for device name
        print("🔍 Scanning for DFU device: $_dfuDeviceName");
        await _nordicDfu.startDfu(
          _dfuDeviceName,
          filePath,
        );
      }
      
      print("✅ DFU process started");
    } catch (e) {
      print("❌ Failed to start DFU: $e");
      rethrow;
    }
  }

  /// Get DFU progress stream
  Stream<DfuProgressState> get progressStream => _nordicDfu.onProgressChanged;

  /// Cancel ongoing DFU process
  Future<void> cancelDfu() async {
    try {
      print("🛑 Cancelling DFU process...");
      await _nordicDfu.abort();
      print("✅ DFU process cancelled");
    } catch (e) {
      print("❌ Failed to cancel DFU: $e");
      rethrow;
    }
  }
} 
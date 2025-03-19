import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../utils/ble_constants.dart';

class AntService {
  bool _isConnected = false;

  /// Connect to BLE device
  Future<void> connectDevice(BluetoothDevice device) async {
    if (_isConnected) {
      print("✅ Already connected to BLE device");
      return;
    }

    try {
      print("🔌 Connecting to BLE device...");
      await device.connect();
      _isConnected = true;
      print("✅ Connected to BLE device");
    } catch (e) {
      print("❌ Failed to connect to BLE device: $e");
      rethrow;
    }
  }

  /// Get Battery Level (Read-Only)
  Future<String> getBatteryLevel(BluetoothDevice device) async {
    try {
      print("🔋 Requesting battery level...");
      await connectDevice(device);
      final service = await device.discoverServices();
      final batteryService = service.firstWhere(
        (s) => s.serviceUuid == BleConstants.batteryService,
        orElse: () => throw Exception('Battery service not found'),
      );
      
      final characteristic = batteryService.characteristics.firstWhere(
        (c) => c.characteristicUuid == BleConstants.batteryLevelChar,
        orElse: () => throw Exception('Battery characteristic not found'),
      );

      final response = await characteristic.read();
      if (response.isNotEmpty) {
        print("✅ Battery Level Response: ${response[0]}%");
        return "${response[0]}%";
      } else {
        print("⚠️ Battery read was empty!");
        return "Unknown%";
      }
    } catch (e) {
      print("❌ Failed to read battery level: $e");
      return "Unknown%";
    }
  }

  /// Get Device ID & Name from `0x1524` (Read-Only)
  Future<Map<String, dynamic>> getDeviceInfo(BluetoothDevice device) async {
    try {
      print("📡 Requesting Device ID & Name...");
      await connectDevice(device);
      final services = await device.discoverServices();
      final service = services.firstWhere(
        (s) => s.serviceUuid == Guid("00001523-0000-1000-8000-00805f9b34fb"),
      );
      
      final characteristic = service.characteristics.firstWhere(
        (c) => c.characteristicUuid == Guid("00001524-0000-1000-8000-00805f9b34fb"),
      );

      final response = await characteristic.read();
      if (response.length < 3) {
        print("⚠️ Invalid response length: ${response.length}");
        return {"deviceId": "Unknown", "deviceName": "Unknown Device"};
      }

      int deviceIdValue = response[0] | (response[1] << 8);
      int nameLength = response[2];
      String deviceName = response.length >= (3 + nameLength)
          ? String.fromCharCodes(response.sublist(3, 3 + nameLength))
          : "Unknown Device";

      print("✅ Device Info - ID: $deviceIdValue, Name: $deviceName");
      return {"deviceId": deviceIdValue.toString(), "deviceName": deviceName};
    } catch (e) {
      print("❌ Failed to read Device ID & Name: $e");
      return {"deviceId": "Unknown", "deviceName": "Unknown Device"};
    }
  }

  /// Start ANT+ Search (0x01 to 0x1601, listen on 0x1602)
  Stream<Map<String, dynamic>> startAntSearch(BluetoothDevice device) async* {
    try {
      await connectDevice(device);
      final services = await device.discoverServices();
      final customService = services.firstWhere(
        (s) => s.serviceUuid == BleConstants.customService,
      );
      
      final controlChar = customService.characteristics.firstWhere(
        (c) => c.characteristicUuid == BleConstants.scanControlChar,
      );
      
      final resultsChar = customService.characteristics.firstWhere(
        (c) => c.characteristicUuid == BleConstants.scanResultsChar,
      );

      print("📡 Subscribing to ANT+ scan results (0x1602) before starting scan...");
      await resultsChar.setNotifyValue(true);

      print("📡 Sending `0x01` to `0x1601` to start scanning...");
      await controlChar.write([0x01], withoutResponse: false);

      await for (final data in resultsChar.lastValueStream) {
        if (data.length < 3) continue;

        final deviceId = data[0] | (data[1] << 8);
        final rssi = data[2];

        print("✅ ANT+ Device Found: ID=$deviceId, RSSI=$rssi dBm");
        yield {
          "deviceId": deviceId,
          "rssi": rssi,
        };
      }
    } catch (e) {
      print("❌ Error in ANT+ search: $e");
    }
  }

  /// Stop ANT+ Scanning
  Future<void> stopAntSearch(BluetoothDevice device) async {
    try {
      print("🛑 Sending `0x02` to `0x1601` to stop ANT+ scanning...");
      final services = await device.discoverServices();
      final customService = services.firstWhere(
        (s) => s.serviceUuid == BleConstants.customService,
      );
      
      final controlChar = customService.characteristics.firstWhere(
        (c) => c.characteristicUuid == BleConstants.scanControlChar,
      );

      await controlChar.write([0x02], withoutResponse: false);
      print("✅ ANT+ Scanning Stopped.");
    } catch (e) {
      print("❌ Failed to stop ANT+ scanning: $e");
      rethrow;
    }
  }

  /// Disconnect BLE device
  Future<void> disconnectDevice(BluetoothDevice device) async {
    try {
      print("🔌 Disconnecting BLE device...");
      await device.disconnect();
      _isConnected = false;
      print("✅ BLE Disconnected Successfully.");
    } catch (e) {
      print("❌ Error disconnecting BLE: $e");
      rethrow;
    }
  }

  /// Save Selected ANT+ Device to `0x1603`
  Future<void> saveSelectedAntDevice(BluetoothDevice device, int antDeviceId) async {
    try {
      final services = await device.discoverServices();
      final customService = services.firstWhere(
        (s) => s.serviceUuid == BleConstants.customService,
      );
      
      final characteristic = customService.characteristics.firstWhere(
        (c) => c.characteristicUuid == BleConstants.selectDeviceChar,
      );

      List<int> value = [antDeviceId & 0xFF, (antDeviceId >> 8) & 0xFF];
      print("💾 Writing ANT+ Device ID to 0x1603: $antDeviceId...");
      await characteristic.write(value, withoutResponse: false);
      print("✅ Successfully wrote to 0x1603!");
    } catch (e) {
      print("❌ Error writing to 0x1603: $e");
      rethrow;
    }
  }
}

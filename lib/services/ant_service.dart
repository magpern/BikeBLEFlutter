import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import '../utils/ble_constants.dart';

class AntService {
  final FlutterReactiveBle _ble = FlutterReactiveBle();

  /// ✅ Get Battery Level (Read-Only)
  Future<String> getBatteryLevel(String deviceId) async {
    final characteristic = QualifiedCharacteristic(
      deviceId: deviceId,
      serviceId: BleConstants.batteryService, // 0x180F
      characteristicId: BleConstants.batteryLevelChar, // 0x2A19
    );

    try {
      print("🔋 Requesting battery level...");
      final response = await _ble.readCharacteristic(characteristic);
      
      if (response.isNotEmpty) {
        print("✅ Battery Level Response: ${response[0]}%");
        return "${response[0]}%"; // Battery percentage
      } else {
        print("⚠️ Battery read was empty!");
        return "Unknown%";
      }
    } catch (e) {
      print("❌ Failed to read battery level: $e");
      return "Unknown%";
    }
  }

  /// ✅ Get Device ID & Name from `0x1524` (Read-Only)
  Future<Map<String, dynamic>> getDeviceInfo(String deviceId) async {
    final characteristic = QualifiedCharacteristic(
      deviceId: deviceId,
      serviceId: Uuid.parse("00001523-0000-1000-8000-00805f9b34fb"), // 0x1523
      characteristicId: Uuid.parse("00001524-0000-1000-8000-00805f9b34fb"), // 0x1524
    );

    try {
      print("📡 Requesting Device ID & Name...");
      final response = await _ble.readCharacteristic(characteristic);

      if (response.length < 3) {
        print("⚠️ Invalid response length: ${response.length}");
        return {"deviceId": "Unknown", "deviceName": "Unknown Device"};
      }

      // ✅ Parse Little Endian Device ID (Bytes 0-1)
      int deviceIdValue = response[0] | (response[1] << 8);

      // ✅ Parse Device Name (ASCII) (Bytes 3-N)
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

  /// ✅ Start ANT+ Search (0x01 to 0x1601, listen on 0x1602)
  Stream<Map<String, dynamic>> startAntSearch(String deviceId) {
    final controlChar = QualifiedCharacteristic(
      deviceId: deviceId,
      serviceId: BleConstants.customService,
      characteristicId: BleConstants.scanControlChar, // 0x1601
    );
    final resultsChar = QualifiedCharacteristic(
      deviceId: deviceId,
      serviceId: BleConstants.customService,
      characteristicId: BleConstants.scanResultsChar, // 0x1602
    );

    _ble.writeCharacteristicWithResponse(controlChar, value: [0x01]); // ✅ Start Scan

    return _ble.subscribeToCharacteristic(resultsChar).map((data) {
      if (data.length < 3) return {};
      return {
        "deviceId": data[0] | (data[1] << 8), // Convert to Little Endian
        "rssi": data[2],
      };
    });
  }
}

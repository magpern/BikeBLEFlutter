import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../utils/ble_constants.dart';
import 'github_service.dart';
import 'dfu_service.dart';
import 'package:logger/logger.dart';

enum DataSourceType {
  antDevice(0),
  keiserM3i(1);

  final int value;
  const DataSourceType(this.value);

  static DataSourceType fromValue(int value) {
    return DataSourceType.values.firstWhere(
      (type) => type.value == value,
      orElse: () => DataSourceType.antDevice,
    );
  }

  @override
  String toString() {
    switch (this) {
      case DataSourceType.antDevice:
        return 'ANT+ Device';
      case DataSourceType.keiserM3i:
        return 'Keiser M3i';
    }
  }
}

class AntService {
  final GitHubService _githubService = GitHubService();
  final DfuService _dfuService = DfuService();
  bool _isConnected = false;
  final Logger log = Logger();

  /// Connect to BLE device
  Future<void> connectDevice(BluetoothDevice device) async {
    if (_isConnected) {
      log.i("Already connected to BLE device");
      return;
    }

    try {
      log.i("Connecting to BLE device...");
      await device.connect(timeout: const Duration(seconds: 10));
      await Future.delayed(const Duration(milliseconds: 1000)); // Give it time to stabilize
      _isConnected = true;
      log.i("Connected to BLE device");
    } catch (e) {
      log.e("Failed to connect to BLE device: $e");
      _isConnected = false;
      rethrow;
    }
  }

  /// Get Battery Level (Read-Only)
  Future<String> getBatteryLevel(BluetoothDevice device) async {
    try {
      log.i("Requesting battery level...");
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
        log.i("Battery Level Response: ${response[0]}%");
        return "${response[0]}%";
      } else {
        log.w("Battery read was empty!");
        return "Unknown%";
      }
    } catch (e) {
      log.e("Failed to read battery level: $e");
      return "Unknown%";
    }
  }

  /// Get Device ID & Name from `0x1524` (Read-Only)
  Future<Map<String, dynamic>> getDeviceInfo(BluetoothDevice device) async {
    try {
      log.i("Requesting Device ID & Name...");
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
        log.w("Invalid response length: ${response.length}");
        return {
          "deviceId": "Unknown", 
          "deviceName": "Unknown Device",
          "dataSourceType": DataSourceType.antDevice,
          "macAddress": "Unknown"
        };
      }

      // Parse Device ID (2 bytes)
      int deviceIdValue = response[0] | (response[1] << 8);
      
      // Parse Name Length and Name
      int nameLength = response[2];
      String deviceName = response.length >= (3 + nameLength)
          ? String.fromCharCodes(response.sublist(3, 3 + nameLength))
          : "Unknown Device";

      // Parse Data Source Type (1 byte)
      int dataSourceTypeOffset = 3 + nameLength;
      DataSourceType dataSourceType = response.length > dataSourceTypeOffset 
          ? DataSourceType.fromValue(response[dataSourceTypeOffset])
          : DataSourceType.antDevice;

      // Parse MAC Address (6 bytes)
      int macOffset = dataSourceTypeOffset + 1;
      String macAddress = "Unknown";
      if (response.length >= macOffset + 6) {
        List<int> macBytes = response.sublist(macOffset, macOffset + 6);
        macAddress = macBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');
      }

      log.i("Device Info - ID: $deviceIdValue, Name: $deviceName, Data Source: ${dataSourceType.toString()}, MAC: $macAddress");
      return {
        "deviceId": deviceIdValue.toString(),
        "deviceName": deviceName,
        "dataSourceType": dataSourceType,
        "macAddress": macAddress
      };
    } catch (e) {
      log.e("Failed to read Device ID & Name: $e");
      return {
        "deviceId": "Unknown", 
        "deviceName": "Unknown Device",
        "dataSourceType": DataSourceType.antDevice,
        "macAddress": "Unknown"
      };
    }
  }

  /// Set Device Info to `0x1524` (Write)
  Future<bool> setDeviceInfo(BluetoothDevice device, {
    required int deviceId,
    required String deviceName,
    required DataSourceType dataSourceType,
    String? macAddress
  }) async {
    try {
      log.i("Setting Device Info (ID, Name, Type, MAC)...");
      await connectDevice(device);
      
      final services = await device.discoverServices();
      final service = services.firstWhere(
        (s) => s.serviceUuid == Guid("00001523-0000-1000-8000-00805f9b34fb"),
      );
      
      final characteristic = service.characteristics.firstWhere(
        (c) => c.characteristicUuid == Guid("00001524-0000-1000-8000-00805f9b34fb"),
      );

      // Validate device name length
      if (deviceName.length > 30) { // BLE_NAME_MAX_LEN is typically 30-31
        deviceName = deviceName.substring(0, 30);
        log.w("Device name truncated to 30 characters");
      }
      
      // Create payload
      List<int> payload = [];
      
      // Device ID (2 bytes)
      payload.add(deviceId & 0xFF);
      payload.add((deviceId >> 8) & 0xFF);
      
      // Name length and name
      payload.add(deviceName.length);
      payload.addAll(deviceName.codeUnits);
      
      // Data source type
      payload.add(dataSourceType.value);
      
      // MAC address (if provided)
      if (macAddress != null && macAddress != "Unknown") {
        // Convert MAC address from string format (xx:xx:xx:xx:xx:xx) to bytes
        List<String> macParts = macAddress.split(':');
        if (macParts.length == 6) {
          for (String part in macParts) {
            payload.add(int.parse(part, radix: 16));
          }
        } else {
          // Add zeros if MAC is invalid
          payload.addAll(List.filled(6, 0));
          log.w("Invalid MAC address format, using zeros");
        }
      } else {
        // Add zeros if no MAC is provided
        payload.addAll(List.filled(6, 0));
      }
      
      log.i("Writing Device Info - ID: $deviceId, Name: $deviceName, " +
            "Data Source: ${dataSourceType.toString()}, MAC: ${macAddress ?? 'None'}");
      
      await characteristic.write(payload, withoutResponse: false);
      log.i("Successfully wrote device info!");
      return true;
    } catch (e) {
      log.e("Failed to write device info: $e");
      return false;
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

      log.i("Subscribing to ANT+ scan results (0x1602) before starting scan...");
      await resultsChar.setNotifyValue(true);

      log.i("Sending `0x01` to `0x1601` to start scanning...");
      await controlChar.write([0x01], withoutResponse: false);

      await for (final data in resultsChar.lastValueStream) {
        if (data.length < 3) continue;

        final deviceId = data[0] | (data[1] << 8);
        // Convert RSSI to signed 8-bit integer
        final rssi = data[2].toSigned(8);

        log.i("ANT+ Device Found: ID=$deviceId, RSSI=$rssi dBm");
        yield {
          "deviceId": deviceId,
          "rssi": rssi,
        };
      }
    } catch (e) {
      log.e("Error in ANT+ search: $e");
    }
  }

  /// Stop ANT+ Scanning
  Future<void> stopAntSearch(BluetoothDevice device) async {
    try {
      log.i("Sending `0x02` to `0x1601` to stop ANT+ scanning...");
      final services = await device.discoverServices();
      final customService = services.firstWhere(
        (s) => s.serviceUuid == BleConstants.customService,
      );
      
      final controlChar = customService.characteristics.firstWhere(
        (c) => c.characteristicUuid == BleConstants.scanControlChar,
      );

      await controlChar.write([0x02], withoutResponse: false);
      log.i("ANT+ Scanning Stopped.");
    } catch (e) {
      log.e("Failed to stop ANT+ scanning: $e");
      rethrow;
    }
  }

  /// Disconnect BLE device
  Future<void> disconnectDevice(BluetoothDevice device) async {
    try {
      log.i("Disconnecting BLE device...");
      await device.disconnect();
      _isConnected = false;
      log.i("BLE Disconnected Successfully.");
    } catch (e) {
      log.e("Error disconnecting BLE: $e");
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
      log.i("Writing ANT+ Device ID to 0x1603: $antDeviceId...");
      await characteristic.write(value, withoutResponse: false);
      log.i("Successfully wrote to 0x1603!");
    } catch (e) {
      log.e("Error writing to 0x1603: $e");
      rethrow;
    }
  }

  /// Get Firmware Version Information
  Future<Map<String, dynamic>> getFirmwareVersion(BluetoothDevice device) async {
    try {
      log.i("Requesting firmware version...");
      await connectDevice(device);
      final services = await device.discoverServices();
      
      // Find Device Information Service (0x180A)
      final deviceInfoService = services.firstWhere(
        (s) => s.serviceUuid == BleConstants.deviceInfoService,
        orElse: () => throw Exception('Device Information Service not found'),
      );
      
      // Find Firmware Revision String Characteristic (0x2A26)
      final characteristic = deviceInfoService.characteristics.firstWhere(
        (c) => c.characteristicUuid == BleConstants.firmwareRevisionChar,
        orElse: () => throw Exception('Firmware Revision String characteristic not found'),
      );

      final response = await characteristic.read();
      if (response.isEmpty) {
        log.w("Empty firmware revision response");
        return {
          "currentVersion": "Unknown",
          "latestVersion": "Unknown",
          "hasUpdate": false
        };
      }

      // Parse firmware version as UTF-8 string
      String currentVersion = String.fromCharCodes(response);
      log.i("Firmware Version: $currentVersion");

      return {
        "currentVersion": currentVersion,
        "latestVersion": "Unknown", // Will be updated when checking for updates
        "hasUpdate": false // Will be updated when checking for updates
      };
    } catch (e) {
      log.e("Failed to read firmware version: $e");
      return {
        "currentVersion": "Unknown",
        "latestVersion": "Unknown",
        "hasUpdate": false
      };
    }
  }

  /// Get Hardware Version Information
  Future<String> getHardwareVersion(BluetoothDevice device) async {
    try {
      log.i("Requesting hardware version...");
      await connectDevice(device);
      final services = await device.discoverServices();
      
      // Find Device Information Service (0x180A)
      final deviceInfoService = services.firstWhere(
        (s) => s.serviceUuid == BleConstants.deviceInfoService,
        orElse: () => throw Exception('Device Information Service not found'),
      );
      
      // Find Hardware Revision String Characteristic (0x2A27)
      final characteristic = deviceInfoService.characteristics.firstWhere(
        (c) => c.characteristicUuid == BleConstants.hardwareRevisionChar,
        orElse: () => throw Exception('Hardware Revision String characteristic not found'),
      );

      final response = await characteristic.read();
      if (response.isEmpty) {
        log.w("Empty hardware revision response");
        return "Unknown";
      }

      // Parse hardware version as UTF-8 string
      String hardwareVersion = String.fromCharCodes(response);
      log.i("Hardware Version: $hardwareVersion");
      return hardwareVersion;
    } catch (e) {
      log.e("Failed to read hardware version: $e");
      return "Unknown";
    }
  }

  /// Check for Firmware Updates
  Future<Map<String, dynamic>> checkFirmwareUpdate(BluetoothDevice device) async {
    try {
      log.i("Checking for firmware updates...");
      
      // Get current firmware version from device
      final currentVersion = (await getFirmwareVersion(device))["currentVersion"];
      
      // Get hardware version for hardware-specific firmware
      final hardwareVersion = await getHardwareVersion(device);
      
      // Get latest version from GitHub
      final githubRelease = await _githubService.getLatestRelease(hardwareVersion: hardwareVersion);
      
      if (!githubRelease['success']) {
        log.e("Failed to fetch GitHub release: ${githubRelease['error']}");
        return {
          "latestVersion": "Unable to check for updates",
          "hasUpdate": false
        };
      }

      final latestVersion = githubRelease['version'];
      final hasUpdate = _githubService.isNewerVersion(currentVersion, latestVersion);

      log.i("Firmware Update Check - Current: $currentVersion, Hardware: $hardwareVersion, Latest: $latestVersion, Update Available: $hasUpdate");
      return {
        "latestVersion": latestVersion,
        "hasUpdate": hasUpdate,
        "downloadUrl": githubRelease['downloadUrl']
      };
    } catch (e) {
      log.e("Failed to check firmware update: $e");
      return {
        "latestVersion": "Unable to check for updates",
        "hasUpdate": false
      };
    }
  }

  /// Update Firmware
  Future<void> updateFirmware(BluetoothDevice device, String filePath) async {
    try {
      log.i("Starting full firmware update process (trigger + scan + update)...");
      
      await _dfuService.performFullDfu(device, filePath);

      log.i("Firmware update process started via DFU Bootloader");
      
      // Wait for the update to complete
      await _dfuService.progressStream.firstWhere((state) => state.state == 'COMPLETED');
      
      // Close the stream after completion
      _dfuService.dispose();
    } catch (e) {
      log.e("Failed to start full firmware update: $e");
      rethrow;
    }
  }

  /// Cancel Firmware Update
  Future<void> cancelFirmwareUpdate() async {
    try {
      await _dfuService.abortDfu();
    } catch (e) {
      log.e("Failed to cancel firmware update: $e");
      rethrow;
    }
  }

  /// Get Firmware Update Progress Stream
  Stream<DfuProgressState> get firmwareUpdateProgress => _dfuService.progressStream;
  
  /// Scan for Keiser M3 devices
  Stream<Map<String, dynamic>> scanForKeiserM3Devices() async* {
    try {
      log.i("Starting scan for Keiser M3 devices...");
      
      // Check if Bluetooth is turned on
      if (await FlutterBluePlus.isAvailable == false) {
        log.e("Bluetooth is not available");
        return;
      }
      
      // Start scanning
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        androidUsesFineLocation: false,
      );
      
      // Listen for scan results
      await for (final result in FlutterBluePlus.scanResults) {
        for (ScanResult r in result) {
          // Filter for Keiser M3 devices (name starts with "M3")
          if (r.device.platformName.startsWith("M3")) {
            // Extract equipment ID from advertising data if available
            int equipmentId = 0;
            String macAddress = r.device.remoteId.str;
            
            // Parse manufacturer-specific data
            if (r.advertisementData.manufacturerData.isNotEmpty) {
              // The equipment ID is typically in the 4th byte of manufacturer data
              // This might need adjustment based on actual data format
              for (List<int> data in r.advertisementData.manufacturerData.values) {
                if (data.length >= 4) {
                  equipmentId = data[3];
                  break;
                }
              }
            }
            
            log.i("Found Keiser M3 - Name: ${r.device.platformName}, MAC: $macAddress, RSSI: ${r.rssi}, Equipment ID: $equipmentId");
            
            yield {
              "device": r.device,
              "name": r.device.platformName,
              "rssi": r.rssi,
              "equipmentId": equipmentId,
              "macAddress": macAddress,
            };
          }
        }
      }
      
      // Stop scanning
      await FlutterBluePlus.stopScan();
      log.i("Scan for Keiser M3 devices completed.");
    } catch (e) {
      log.e("Error scanning for Keiser M3 devices: $e");
      await FlutterBluePlus.stopScan();
    }
  }
}

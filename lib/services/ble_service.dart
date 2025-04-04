import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../utils/ble_constants.dart';
import 'package:logger/logger.dart';

class BleService {
  final List<BluetoothDevice> _foundDevices = [];
  final Map<String, int> _deviceRssi = {}; // Map to store RSSI values
  final Logger log = Logger();

  /// Get RSSI for a device
  int? getRssi(BluetoothDevice device) {
    return _deviceRssi[device.remoteId.str];
  }

  /// Scan for BLE devices advertising FTMS and Custom Service
  Stream<List<BluetoothDevice>> scanForDevices() {
    _foundDevices.clear();
    _deviceRssi.clear(); // Clear RSSI values
    
    // Start scanning for all devices first
    FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 10),
    );
    
    // Create a stream that emits the current list of devices whenever new results come in
    return FlutterBluePlus.scanResults.map((results) {
      bool listChanged = false;
      for (ScanResult r in results) {
        log.i("Found device: ${r.device.platformName} (${r.device.remoteId})");
        log.i("Services: ${r.advertisementData.serviceUuids}");
        log.i("RSSI: ${r.rssi} dBm"); // Log the RSSI value
        
        // Check if device advertises our required services
        if (r.advertisementData.serviceUuids.contains(BleConstants.ftmsService) ||
            r.advertisementData.serviceUuids.contains(BleConstants.customService)) {
          log.i("Found matching device: ${r.device.platformName}");
          
          // Store/update RSSI value
          _deviceRssi[r.device.remoteId.str] = r.rssi;
          
          if (!_foundDevices.any((d) => d.remoteId == r.device.remoteId)) {
            _foundDevices.add(r.device);
            listChanged = true;
          }
        }
      }
      if (listChanged) {
        return List.from(_foundDevices);
      }
      return _foundDevices;
    });
  }

  /// Start scanning
  Future<void> startScan() async {
    await FlutterBluePlus.startScan(
      withServices: [
        Guid(BleConstants.ftmsService.str),
        Guid(BleConstants.customService.str),
      ],
    );
  }

  /// Stop scanning
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
  }
}

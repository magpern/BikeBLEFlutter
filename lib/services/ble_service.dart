import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import '../utils/ble_constants.dart';

class BleService {
  final FlutterReactiveBle _ble = FlutterReactiveBle();
  final List<DiscoveredDevice> _foundDevices = [];

  /// ✅ Scan for BLE devices advertising FTMS (0x1826) and Custom Service (0x1600)
  Stream<List<DiscoveredDevice>> scanForDevices() {
    _foundDevices.clear(); // Reset list before scanning
    return _ble.scanForDevices(
      withServices: [
        BleConstants.ftmsService,    // ✅ FTMS (0x1826)
        BleConstants.customService,  // ✅ Custom ANT+ BLE (0x1600)
      ],
      scanMode: ScanMode.lowLatency,
    ).map((device) {
      // ✅ Only add devices if they explicitly advertise FTMS or Custom ANT+ Service
      if (_containsService(device, BleConstants.ftmsService) || _containsService(device, BleConstants.customService)) {
        if (!_foundDevices.any((d) => d.id == device.id)) {
          _foundDevices.add(device);
        }
      }
      return List.from(_foundDevices);
    });
  }

  /// ✅ Helper Function: Check if a device advertises the given service
  bool _containsService(DiscoveredDevice device, Uuid serviceUuid) {
    return device.serviceUuids.contains(serviceUuid);
  }
}

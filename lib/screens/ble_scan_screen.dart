import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import '../services/ble_service.dart';
import '../screens/device_details_screen.dart';

class BleScanScreen extends StatefulWidget {
  const BleScanScreen({super.key});

  @override
  BleScanScreenState createState() => BleScanScreenState();
}

class BleScanScreenState extends State<BleScanScreen> {
  final BleService _bleService = BleService();
  List<DiscoveredDevice> _devices = [];
  bool _isScanning = false;
  bool? _isBluetoothEnabled;
  bool _bleStatusChecked = false;
  StreamSubscription<BleStatus>? _bleStatusSubscription;
  String? _previouslySelectedDeviceId; // ✅ Store Previously Selected Device
  Timer? _scanTimeoutTimer;

  @override
  void initState() {
    super.initState();
    _checkBluetoothStatus();
  }

  @override
  void dispose() {
    _bleStatusSubscription?.cancel();
    _scanTimeoutTimer?.cancel(); // ✅ Ensure Timer is Cancelled
    super.dispose();
  }

  /// ✅ Check Bluetooth status and update UI
  void _checkBluetoothStatus() {
    _bleStatusSubscription = FlutterReactiveBle().statusStream.listen((status) {
      setState(() {
        _isBluetoothEnabled = (status == BleStatus.ready);
        _bleStatusChecked = true;
      });
    });
  }

  /// ✅ Request permissions and toggle scan
  Future<void> _toggleScan() async {
    if (_isScanning) {
      _stopScan();
    } else {
      Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();

      if (statuses[Permission.bluetoothScan]!.isGranted &&
          statuses[Permission.bluetoothConnect]!.isGranted &&
          statuses[Permission.location]!.isGranted) {
        _startScan();
      } else {
        print("❌ Permissions not granted!");
      }
    }
  }

  void _startScan() {
    setState(() {
      _isScanning = true;
      _devices.clear();
    });

    _bleService.scanForDevices().listen((devices) {
      if (mounted) {
        setState(() {
          _devices = _sortDevices(devices);
        });
      }
    });

    // ✅ Stop scan automatically after 10 seconds
    _scanTimeoutTimer = Timer(const Duration(seconds: 10), _stopScan);
  }

  void _stopScan() {
    setState(() {
      _isScanning = false;
      _scanTimeoutTimer?.cancel();
    });
  }

  /// ✅ Sort devices, moving previously selected device to the top
  List<DiscoveredDevice> _sortDevices(List<DiscoveredDevice> devices) {
    devices.sort((a, b) {
      if (a.id == _previouslySelectedDeviceId) return -1;
      if (b.id == _previouslySelectedDeviceId) return 1;
      return 0;
    });
    return devices;
  }

  /// ✅ Select BLE Device and Navigate to a New Instance of Device Details Screen
  void _selectDevice(DiscoveredDevice device) {
    print("✅ Selected BLE Device: ${device.id}");

    // ✅ Stop scanning when a device is selected
    _stopScan();

    setState(() {
      _previouslySelectedDeviceId = device.id; // ✅ Store selection for future scans
    });

    // ✅ Ensure a New Screen is Created Each Time
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DeviceDetailsScreen(device: device),
        settings: RouteSettings(name: "/device_details_${device.id}_${DateTime.now().millisecondsSinceEpoch}"), // ✅ Forces new instance
      ),
    ).then((_) {
      // ✅ Ensure BLE scanning resets when returning to this page
      setState(() {
        _isScanning = false;
      });
    });
  } 

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("BikeBLE Setup")),
      body: Column(
        children: [
          // ✅ Description Section
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text(
                  "Welcome to BikeBLE Setup",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Use this app to find your BikeBLE device and link it to a specific bike at your gym.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ],
            ),
          ),

          // ✅ Bluetooth Disabled Banner (Only appears if BLE is off)
          if (_bleStatusChecked && _isBluetoothEnabled == false)
            Container(
              padding: const EdgeInsets.all(10),
              color: Colors.red,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.bluetooth_disabled, color: Colors.white),
                  SizedBox(width: 8),
                  Text("Bluetooth is turned off!", style: TextStyle(color: Colors.white, fontSize: 16)),
                ],
              ),
            ),

          // ✅ Scan Button
          ElevatedButton(
            onPressed: _isBluetoothEnabled == true ? _toggleScan : null,
            child: Text(_isScanning ? "Stop Scanning" : "Find Your BikeBLE Device"),
          ),

          // ✅ Section Header for Found Devices
          if (_devices.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 16.0, left: 16.0, right: 16.0),
              child: Text(
                "Available BikeBLE Devices",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),

          // ✅ BLE Device List (With "Select" Button, ANT+ Icon & RSSI)
          Expanded(
            child: _devices.isEmpty
                ? _isScanning
                    ? const Padding(
                        padding: EdgeInsets.only(top: 10), // ✅ Subtle Spinner Positioning
                        child: CircularProgressIndicator(),
                      )
                    : const SizedBox() // ✅ No spinner when scanning is off
                : ListView.builder(
                    itemCount: _devices.length,
                    itemBuilder: (context, index) {
                      final device = _devices[index];
                      return ListTile(
                        leading: const Icon(Icons.directions_bike, color: Colors.blue), // ✅ ANT+ Bike Icon
                        title: Text(device.name.isNotEmpty ? device.name : "Unknown Device"),
                        subtitle: Row(
                          children: [
                            const Icon(Icons.wifi, color: Colors.green), // ✅ RSSI Icon
                            const SizedBox(width: 5),
                            Text("RSSI: ${device.rssi} dBm"),
                          ],
                        ),
                        trailing: ElevatedButton(
                          onPressed: () => _selectDevice(device),
                          child: const Text("Select"), // ✅ Button stays "Select"
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

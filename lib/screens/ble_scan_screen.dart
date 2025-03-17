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

  @override
  void initState() {
    super.initState();
    _checkBluetoothStatus();
  }

  @override
  void dispose() {
    _bleStatusSubscription?.cancel();
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
          _devices = devices;
        });
      }
    });
  }

  void _stopScan() {
    setState(() {
      _isScanning = false;
      _devices.clear();
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

          // ✅ BLE Device List (Now opens details screen on tap)
          Expanded(
            child: ListView.builder(
              itemCount: _devices.length,
              itemBuilder: (context, index) {
                final device = _devices[index];
                return ListTile(
                  title: Text(device.name.isNotEmpty ? device.name : "Unknown Device"),
                  subtitle: Text("ID: ${device.id}"),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DeviceDetailsScreen(device: device),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

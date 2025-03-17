import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import '../services/ant_service.dart';

class DeviceDetailsScreen extends StatefulWidget {
  final DiscoveredDevice device;

  const DeviceDetailsScreen({super.key, required this.device});

  @override
  DeviceDetailsScreenState createState() => DeviceDetailsScreenState();
}

class DeviceDetailsScreenState extends State<DeviceDetailsScreen> {
  final AntService _antService = AntService();
  String _deviceName = "Loading...";
  String _batteryStatus = "Loading...";
  String _deviceId = "Loading...";
  final List<Map<String, dynamic>> _antDevices = [];

  @override
  void initState() {
    super.initState();
    _fetchDeviceInfo();
  }

  /// ✅ Fetch Battery First → Then Name → Then Device ID → Then Start ANT+ Scan
  Future<void> _fetchDeviceInfo() async {
    try {
      // ✅ 1. Read Battery Level First
      final batteryStatus = await _antService.getBatteryLevel(widget.device.id);

      // ✅ 2. Read Device Info (ID & Name)
      final deviceInfo = await _antService.getDeviceInfo(widget.device.id);
      final deviceName = deviceInfo["deviceName"];
      final deviceId = deviceInfo["deviceId"];

      if (mounted) {
        setState(() {
          _deviceName = deviceName;
          _batteryStatus = batteryStatus;
          _deviceId = deviceId;
        });
      }

      // ✅ 3. Start ANT+ Device Search After Everything is Done
      _startAntSearch();
    } catch (e) {
      print("❌ Error fetching device info: $e");
    }
  }

  /// ✅ Starts ANT+ Device Search
  void _startAntSearch() {
    _antService.startAntSearch(widget.device.id).listen((antDevice) {
      if (mounted) {
        setState(() {
          _antDevices.add(antDevice);
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_deviceName)),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("🔋 Battery: $_batteryStatus", style: const TextStyle(fontSize: 18)),
            Text("📶 Signal Strength: ${widget.device.rssi} dBm", style: const TextStyle(fontSize: 18)),
            Text("🔢 Current Device ID: $_deviceId", style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 20),

            const Text("🔍 Found ANT+ Devices:", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Expanded(
              child: ListView.builder(
                itemCount: _antDevices.length,
                itemBuilder: (context, index) {
                  final antDevice = _antDevices[index];
                  return ListTile(
                    title: Text("Device ID: ${antDevice['deviceId']}"),
                    subtitle: Text("RSSI: ${antDevice['rssi']} dBm"),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

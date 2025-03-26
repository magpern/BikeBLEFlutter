import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../services/ant_service.dart';

class DeviceDetailsScreen extends StatefulWidget {
  final BluetoothDevice device;

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
  bool _isFetchingData = true; // ✅ Track if data is still loading

  @override
  void initState() {
    super.initState();
    _fetchDeviceInfo();
  }

  /// ✅ Fetch Device Info in the correct order
  Future<void> _fetchDeviceInfo() async {
    try {
      // ✅ 1. Connect to device first
      await _antService.connectDevice(widget.device);

      // ✅ 2. Read Device Info (ID & Name)
      final deviceInfo = await _antService.getDeviceInfo(widget.device);
      final deviceName = deviceInfo["deviceName"];
      final deviceId = deviceInfo["deviceId"];

      // ✅ 3. Read Battery Level
      final batteryStatus = await _antService.getBatteryLevel(widget.device);

      if (mounted) {
        setState(() {
          _deviceName = deviceName;
          _batteryStatus = batteryStatus;
          _deviceId = deviceId;
          _isFetchingData = false;
        });
      }

      // ✅ 4. Start ANT+ Device Search After Everything is Done
      _startAntSearch();
    } catch (e) {
      print("❌ Error fetching device info: $e");
      if (mounted) {
        setState(() {
          _deviceName = "Connection Failed";
          _batteryStatus = "Unknown";
          _deviceId = "Unknown";
          _isFetchingData = false;
        });
      }
    }
  }

  /// ✅ Starts ANT+ Device Search
  void _startAntSearch() {
    setState(() {
      _antDevices.clear(); // Clear the list before starting new search
    });
    
    _antService.startAntSearch(widget.device).listen((antDevice) {
      if (mounted) {
        setState(() {
          _antDevices.add(antDevice);
        });
      }
    });
  }

  /// ✅ Save Selected ANT+ Device to `0x1603`
  void _saveSelectedAntDevice(int antDeviceId) async {
    final navigatorState = Navigator.of(context);
    
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text("Confirm Selection"),
          content: Text("Are you sure you want to save Device ID: $antDeviceId?"),
          actions: [
            TextButton(
              onPressed: () {
                navigatorState.pop(); // Close dialog
              },
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () async {
                navigatorState.pop(); // Close dialog first

                try {
                  print("🛑 Stopping ANT+ scan...");
                  await _antService.stopAntSearch(widget.device);

                  print("💾 Saving ANT+ Device ID: $antDeviceId...");
                  await _antService.saveSelectedAntDevice(widget.device, antDeviceId);
                  print("✅ ANT+ Device ID saved successfully!");

                  // Navigate back to previous screen after successful save
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Device saved successfully"),
                        duration: Duration(seconds: 1),
                      ),
                    );
                    await Future.delayed(const Duration(milliseconds: 500));
                    navigatorState.pop(); // Return to previous screen
                  }
                } catch (e) {
                  print("❌ Failed to save ANT+ Device: $e");
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Failed to save device"),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                }
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
  }


  @override
  void dispose() {
    print("🔌 Stopping ANT+ search before closing BLE connection...");
    
    // Stop ANT+ search and disconnect BLE in a fire-and-forget manner
    _cleanupConnections();
    
    super.dispose(); // Call super.dispose() immediately
  }

  // Separate method to handle the async cleanup
  Future<void> _cleanupConnections() async {
    try {
      await _antService.stopAntSearch(widget.device); // ✅ Stop ANT+ scanning first
    } catch (e) {
      print("❌ Failed to stop ANT+ search: $e");
    }

    print("🔌 Disconnecting BLE connection...");
    try {
      await _antService.disconnectDevice(widget.device); // ✅ Properly disconnect BLE
    } catch (e) {
      print("❌ Failed to disconnect BLE: $e");
    }
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
            _isFetchingData
                ? Center(child: CircularProgressIndicator()) // ✅ Show loading indicator
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("🔋 Battery: $_batteryStatus", style: const TextStyle(fontSize: 18)),
                      Text("📶 Signal Strength: ${_antDevices.isNotEmpty ? _antDevices.first['rssi'] : 'N/A'} dBm", style: const TextStyle(fontSize: 18)),
                      Text("🔢 Current Device ID: $_deviceId", style: const TextStyle(fontSize: 18)),
                    ],
                  ),
            const SizedBox(height: 20),
            const Text("🔍 Found ANT+ Devices:", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Expanded(
              child: _antDevices.isEmpty
                  ? Center(child: CircularProgressIndicator()) // ✅ Show loader while scanning
                  : ListView.builder(
                      itemCount: _antDevices.length,
                      itemBuilder: (context, index) {
                        final antDevice = _antDevices[index];
                        return ListTile(
                          title: Text("Device ID: ${antDevice['deviceId']}"),
                          subtitle: Text("RSSI: ${antDevice['rssi']} dBm"),
                          trailing: ElevatedButton(
                            onPressed: () => _saveSelectedAntDevice(antDevice['deviceId']),
                            child: Text("Select"),
                          ),
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

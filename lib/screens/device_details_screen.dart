import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../services/ant_service.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:async';

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
  String _currentFirmwareVersion = "Loading...";
  String _latestFirmwareVersion = "Loading...";
  bool _hasUpdateAvailable = false;
  bool _isCheckingFirmware = false;
  bool _isUpdatingFirmware = false;
  String? _updateError;
  final List<Map<String, dynamic>> _antDevices = [];
  bool _isFetchingData = true;
  StreamSubscription? _firmwareUpdateProgressSubscription;

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

      // ✅ 4. Read Firmware Version
      final firmwareInfo = await _antService.getFirmwareVersion(widget.device);
      final currentVersion = firmwareInfo["currentVersion"];
      final latestVersion = firmwareInfo["latestVersion"];
      final hasUpdate = firmwareInfo["hasUpdate"];

      if (mounted) {
        setState(() {
          _deviceName = deviceName;
          _batteryStatus = batteryStatus;
          _deviceId = deviceId;
          _currentFirmwareVersion = currentVersion;
          _latestFirmwareVersion = latestVersion;
          _hasUpdateAvailable = hasUpdate;
          _isFetchingData = false;
        });
      }

      // ✅ 5. Start ANT+ Device Search After Everything is Done
      _startAntSearch();
    } catch (e) {
      print("❌ Error fetching device info: $e");
      if (mounted) {
        setState(() {
          _deviceName = "Connection Failed";
          _batteryStatus = "Unknown";
          _deviceId = "Unknown";
          _currentFirmwareVersion = "Unknown";
          _latestFirmwareVersion = "Unknown";
          _hasUpdateAvailable = false;
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

  /// Check for firmware updates
  Future<void> _checkForUpdates() async {
    if (_isCheckingFirmware) return;

    setState(() {
      _isCheckingFirmware = true;
    });

    try {
      final firmwareInfo = await _antService.checkFirmwareUpdate(widget.device);
      if (mounted) {
        setState(() {
          _latestFirmwareVersion = firmwareInfo["latestVersion"];
          _hasUpdateAvailable = firmwareInfo["hasUpdate"];
          _isCheckingFirmware = false;
        });
      }
    } catch (e) {
      print("❌ Error checking firmware update: $e");
      if (mounted) {
        setState(() {
          _isCheckingFirmware = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to check for updates")),
        );
      }
    }
  }

  /// Update firmware
  Future<void> _updateFirmware() async {
    if (_isUpdatingFirmware) return;

    setState(() {
      _isUpdatingFirmware = true;
      _updateError = null;
    });

    try {
      // Get the firmware file path from the GitHub release
      final updateInfo = await _antService.checkFirmwareUpdate(widget.device);
      if (!updateInfo['hasUpdate'] || updateInfo['downloadUrl'] == null) {
        throw Exception('No update available or download URL not found');
      }

      // Download the firmware file
      final response = await http.get(Uri.parse(updateInfo['downloadUrl']));
      if (response.statusCode != 200) {
        throw Exception('Failed to download firmware file');
      }

      // Save the file temporarily
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/firmware.zip';
      await File(filePath).writeAsBytes(response.bodyBytes);

      // Start firmware update
      await _antService.updateFirmware(widget.device, filePath);

      // Listen to update progress
      _firmwareUpdateProgressSubscription?.cancel();
      _firmwareUpdateProgressSubscription = _antService.firmwareUpdateProgress.listen(
        (progress) {
          if (mounted) {
            setState(() {
              // Update UI with progress information
              // The exact progress type will depend on the nordic_dfu package
            });
          }
        },
        onError: (error) {
          if (mounted) {
            setState(() {
              _updateError = error.toString();
              _isUpdatingFirmware = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Update failed: $error')),
            );
          }
        },
        onDone: () {
          if (mounted) {
            setState(() {
              _isUpdatingFirmware = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Firmware update completed')),
            );
            // Refresh device info
            _fetchDeviceInfo();
          }
        },
      );
    } catch (e) {
      print("❌ Error updating firmware: $e");
      if (mounted) {
        setState(() {
          _updateError = e.toString();
          _isUpdatingFirmware = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update failed: $e')),
        );
      }
    }
  }

  /// Cancel firmware update
  Future<void> _cancelFirmwareUpdate() async {
    try {
      await _antService.cancelFirmwareUpdate();
      if (mounted) {
        setState(() {
          _isUpdatingFirmware = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Firmware update cancelled')),
        );
      }
    } catch (e) {
      print("❌ Error cancelling firmware update: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to cancel update: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _firmwareUpdateProgressSubscription?.cancel();
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
                ? Center(child: CircularProgressIndicator())
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("🔋 Battery: $_batteryStatus", style: const TextStyle(fontSize: 18)),
                      Text("📶 Signal Strength: ${_antDevices.isNotEmpty ? _antDevices.first['rssi'] : 'N/A'} dBm", style: const TextStyle(fontSize: 18)),
                      Text("🔢 Current Device ID: $_deviceId", style: const TextStyle(fontSize: 18)),
                      const SizedBox(height: 20),
                      // Firmware Section
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "📱 Firmware",
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                "Current Version: $_currentFirmwareVersion",
                                style: const TextStyle(fontSize: 16),
                              ),
                              if (_hasUpdateAvailable) ...[
                                const SizedBox(height: 8),
                                Text(
                                  "Latest Version: $_latestFirmwareVersion",
                                  style: const TextStyle(fontSize: 16),
                                ),
                              ],
                              if (_updateError != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  "Error: $_updateError",
                                  style: const TextStyle(fontSize: 16, color: Colors.red),
                                ),
                              ],
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  ElevatedButton(
                                    onPressed: (_isCheckingFirmware || _isUpdatingFirmware) ? null : _checkForUpdates,
                                    child: const Text("Check for Update"),
                                  ),
                                  if (_hasUpdateAvailable)
                                    ElevatedButton(
                                      onPressed: (_isCheckingFirmware || _isUpdatingFirmware) ? null : _updateFirmware,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        foregroundColor: Colors.white,
                                      ),
                                      child: Text(_isUpdatingFirmware ? "Updating..." : "Update Firmware"),
                                    ),
                                  if (_isUpdatingFirmware)
                                    ElevatedButton(
                                      onPressed: _cancelFirmwareUpdate,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red,
                                        foregroundColor: Colors.white,
                                      ),
                                      child: const Text("Cancel Update"),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
            const SizedBox(height: 20),
            const Text("🔍 Found ANT+ Devices:", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Expanded(
              child: _antDevices.isEmpty
                  ? Center(child: CircularProgressIndicator())
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

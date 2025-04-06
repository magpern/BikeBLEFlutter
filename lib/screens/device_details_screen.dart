import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../services/ant_service.dart';
import '../services/dfu_service.dart';
import 'ble_scan_screen.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:async';
import 'package:logger/logger.dart';

class DeviceDetailsScreen extends StatefulWidget {
  final BluetoothDevice device;
  final String? antDeviceId;

  const DeviceDetailsScreen({
    super.key,
    required this.device,
    this.antDeviceId,
  });

  @override
  State<DeviceDetailsScreen> createState() => _DeviceDetailsScreenState();
}

class _DeviceDetailsScreenState extends State<DeviceDetailsScreen> {
  final AntService _antService = AntService();
  final Logger log = Logger();
  String _deviceName = "Loading...";
  String _batteryStatus = "Loading...";
  String _deviceId = "Loading...";
  String _currentFirmwareVersion = "Loading...";
  bool _isFetchingData = true;
  bool _isUpdatingFirmware = false;
  String? _updateError;
  double _updateProgress = 0.0;
  String _updateState = '';
  final List<Map<String, dynamic>> _antDevices = [];
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

      if (mounted) {
        setState(() {
          _deviceName = deviceName;
          _batteryStatus = batteryStatus;
          _deviceId = deviceId;
          _currentFirmwareVersion = currentVersion;
          _isFetchingData = false;
        });
      }

      // ✅ 5. Start ANT+ Device Search After Everything is Done
      _startAntSearch();

      // ✅ 6. Check for firmware updates in background
      _checkForUpdates();
    } catch (e) {
      log.e("Error fetching device info: $e");
      if (mounted) {
        setState(() {
          _deviceName = "Connection Failed";
          _batteryStatus = "Unknown";
          _deviceId = "Unknown";
          _currentFirmwareVersion = "Unknown";
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
          // Add the new device to the list
          _antDevices.add(antDevice);
          // Sort the list by RSSI (strongest signal first)
          _antDevices.sort((a, b) => b['rssi'].compareTo(a['rssi']));
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
                  log.i("Stopping ANT+ scan...");
                  await _antService.stopAntSearch(widget.device);

                  log.i("Saving ANT+ Device ID: $antDeviceId...");
                  await _antService.saveSelectedAntDevice(widget.device, antDeviceId);
                  log.i("ANT+ Device ID saved successfully!");

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
                  log.e("Failed to save ANT+ Device: $e");
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

  /// Check for firmware updates in background
  Future<void> _checkForUpdates() async {
    try {
      final firmwareInfo = await _antService.checkFirmwareUpdate(widget.device);
      if (mounted && firmwareInfo["hasUpdate"]) {
        _showUpdateDialog(firmwareInfo);
      }
    } catch (e) {
      log.e("Error checking firmware update: $e");
    }
  }

  /// Show update dialog
  void _showUpdateDialog(Map<String, dynamic> firmwareInfo) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Firmware Available'),
        content: Text(
          'A new firmware version ${firmwareInfo["latestVersion"]} is available.\n'
          'Current version: $_currentFirmwareVersion\n\n'
          'Would you like to update now?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Not Now'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _updateFirmware(firmwareInfo);
            },
            child: const Text('Update Now'),
          ),
        ],
      ),
    );
  }

  Future<void> _updateFirmware(Map<String, dynamic> updateInfo) async {
    if (_isUpdatingFirmware) return;

    setState(() {
      _isUpdatingFirmware = true;
      _updateError = null;
      _updateProgress = 0.0;
      _updateState = 'PREPARING';
    });

    try {
      final url = updateInfo['downloadUrl'];
      if (url == null) {
        throw Exception('Download URL not found');
      }

      log.i('Downloading firmware from: $url');

      // Download the firmware file
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw Exception('Failed to download firmware file (status: ${response.statusCode})');
      }

      // Save the file temporarily
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/firmware.zip';
      final file = await File(filePath).writeAsBytes(response.bodyBytes);

      final fileSize = await file.length();
      log.i('Firmware saved to: $filePath');
      log.i('Firmware size: $fileSize bytes (${(fileSize / 1024).toStringAsFixed(2)} KB)');

      // Set up progress stream subscription before starting the update
      _firmwareUpdateProgressSubscription?.cancel();
      log.i("Setting up progress stream subscription");
      _firmwareUpdateProgressSubscription = _antService.firmwareUpdateProgress.listen(
        (DfuProgressState progress) {
          if (mounted) {
            log.i('UI received progress update: ${progress.progress} - ${progress.state}');
            log.i('Current UI state: mounted=$mounted, _isUpdatingFirmware=$_isUpdatingFirmware');
            setState(() {
              _updateProgress = progress.progress;
              _updateState = progress.state;
              log.i('UI state updated: progress=$_updateProgress, state=$_updateState');
            });

            // Check if we've reached the COMPLETED state
            if (progress.state == 'COMPLETED') {
              log.i('Firmware update completed, preparing to return to main screen');
              setState(() {
                _isUpdatingFirmware = false;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Firmware update completed')),
              );
              
              // Wait 2 seconds and then return to main screen
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) {
                  log.i('Attempting to return to main screen');
                  Navigator.of(context).pop();
                  // Cancel the subscription after navigation
                  _firmwareUpdateProgressSubscription?.cancel();
                } else {
                  log.w('Widget not mounted when attempting to return to main screen');
                }
              });
            }
          } else {
            log.w('UI not mounted when receiving progress update');
          }
        },
        onError: (error) {
          if (mounted) {
            log.e('Progress stream error: $error');
            setState(() {
              _updateError = error.toString();
              _isUpdatingFirmware = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Update failed: $error')),
            );
          }
        },
      );
      log.i("Progress stream subscription set up");

      // Start firmware update after setting up the subscription
      await _antService.updateFirmware(widget.device, filePath);
    } catch (e) {
      log.e("Error updating firmware: $e");
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
      log.e("Error cancelling firmware update: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to cancel update: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    if (!_isUpdatingFirmware) {
      _firmwareUpdateProgressSubscription?.cancel();
      log.i("Stopping ANT+ search before closing BLE connection...");
      
      // Stop ANT+ search and disconnect BLE in a fire-and-forget manner
      _cleanupConnections();
    }
    
    super.dispose(); // Call super.dispose() immediately
  }

  // Separate method to handle the async cleanup
  Future<void> _cleanupConnections() async {
    try {
      await _antService.stopAntSearch(widget.device); // ✅ Stop ANT+ scanning first
    } catch (e) {
      log.e("Failed to stop ANT+ search: $e");
    }

    log.i("Disconnecting BLE connection...");
    try {
      await _antService.disconnectDevice(widget.device); // ✅ Properly disconnect BLE
    } catch (e) {
      log.e("Failed to disconnect BLE: $e");
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
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("🔋 Battery: $_batteryStatus", style: const TextStyle(fontSize: 18)),
                      Text("📶 Signal Strength: ${_antDevices.isNotEmpty ? _antDevices.first['rssi'] : 'N/A'} dBm", style: const TextStyle(fontSize: 18)),
                      Text("🔢 Current Device ID: $_deviceId", style: const TextStyle(fontSize: 18)),
                      Text("📱 Firmware Version: $_currentFirmwareVersion", style: const TextStyle(fontSize: 18)),
                      if (_isUpdatingFirmware) ...[
                        const SizedBox(height: 8),
                        LinearProgressIndicator(value: _updateProgress),
                        const SizedBox(height: 8),
                        Text(
                          '${(_updateProgress * 100).toStringAsFixed(1)}% - $_updateState',
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: _cancelFirmwareUpdate,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text("Cancel Update"),
                        ),
                      ],
                      const SizedBox(height: 20),
                    ],
                  ),
            if (!_isUpdatingFirmware) ...[
              const SizedBox(height: 20),
              const Text("🔍 Found ANT+ Devices:", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              Expanded(
                child: _antDevices.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        itemCount: _antDevices.length,
                        itemBuilder: (context, index) {
                          final antDevice = _antDevices[index];
                          return ListTile(
                            title: Text("Device ID: ${antDevice['deviceId']}"),
                            subtitle: Text("RSSI: ${antDevice['rssi']} dBm"),
                            trailing: ElevatedButton(
                              onPressed: () => _saveSelectedAntDevice(antDevice['deviceId']),
                              child: const Text("Select"),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

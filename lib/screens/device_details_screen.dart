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
  String _hardwareVersion = "Loading...";
  int _bleRssi = 0;
  bool _isFetchingData = true;
  bool _isUpdatingFirmware = false;
  String? _updateError;
  double _updateProgress = 0.0;
  String _updateState = '';
  final List<Map<String, dynamic>> _antDevices = [];
  final List<Map<String, dynamic>> _keiserDevices = [];
  DataSourceType _dataSourceType = DataSourceType.antDevice;
  String _macAddress = "Unknown";
  StreamSubscription? _firmwareUpdateProgressSubscription;
  StreamSubscription? _keiserScanSubscription;
  StreamSubscription? _antSearchSubscription;
  final _deviceNameRegex = RegExp(r'^[A-Za-z0-9]{1,8}$');
  StreamSubscription<int>? _rssiSubscription;

  @override
  void initState() {
    super.initState();
    _fetchDeviceInfo();
  }

  @override
  void dispose() {
    _rssiSubscription?.cancel();
    _keiserScanSubscription?.cancel();
    _antSearchSubscription?.cancel();
    if (!_isUpdatingFirmware) {
      _firmwareUpdateProgressSubscription?.cancel();
      log.i("Stopping searches before closing BLE connection...");
      
      // Stop ANT+ search and disconnect BLE in a fire-and-forget manner
      _cleanupConnections();
    }
    
    super.dispose(); // Call super.dispose() immediately
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
      final dataSourceType = deviceInfo["dataSourceType"];
      final macAddress = deviceInfo["macAddress"];

      // ✅ 3. Read Battery Level
      final batteryStatus = await _antService.getBatteryLevel(widget.device);

      // ✅ 4. Read Firmware Version
      final firmwareInfo = await _antService.getFirmwareVersion(widget.device);
      final currentVersion = firmwareInfo["currentVersion"];
      
      // 5. Read Hardware Version
      final hardwareVersion = await _antService.getHardwareVersion(widget.device);
      
      // 6. Start reading RSSI updates for BLE device
      _startRssiUpdates();

      if (mounted) {
        setState(() {
          _deviceName = deviceName;
          _batteryStatus = batteryStatus;
          _deviceId = deviceId;
          _dataSourceType = dataSourceType is DataSourceType ? dataSourceType : DataSourceType.antDevice;
          _macAddress = macAddress;
          _currentFirmwareVersion = currentVersion;
          _hardwareVersion = hardwareVersion;
          _isFetchingData = false;
        });
      }

      // Start device search based on data source type
      if (_dataSourceType == DataSourceType.antDevice) {
        // Start ANT+ search for ANT device mode
        _startAntSearch();
      } else if (_dataSourceType == DataSourceType.keiserM3i) {
        // Start Keiser M3 device search for Keiser mode
        _startKeiserSearch();
      }

      // ✅ 8. Check for firmware updates in background
      _checkForUpdates();
    } catch (e) {
      log.e("Error fetching device info: $e");
      if (mounted) {
        setState(() {
          _deviceName = "Connection Failed";
          _batteryStatus = "Unknown";
          _deviceId = "Unknown";
          _macAddress = "Unknown";
          _currentFirmwareVersion = "Unknown";
          _hardwareVersion = "Unknown";
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
    
    // Cancel any existing subscription
    _antSearchSubscription?.cancel();
    
    // Create new subscription
    _antSearchSubscription = _antService.startAntSearch(widget.device).listen((antDevice) {
      if (mounted) {
        setState(() {
          // Add the new device to the list
          _antDevices.add(antDevice);
          // Sort the list by RSSI (strongest signal first)
          _antDevices.sort((a, b) => b['rssi'].compareTo(a['rssi']));
        });
      }
    }, onError: (e) {
      log.e("Error in ANT+ search: $e");
    });
  }

  /// Start Keiser M3 Device Search
  void _startKeiserSearch() {
    setState(() {
      _keiserDevices.clear(); // Clear the list before starting new search
    });
    
    _keiserScanSubscription?.cancel();
    _keiserScanSubscription = _antService.scanForKeiserM3Devices().listen((keiserDevice) {
      if (mounted) {
        setState(() {
          // Check if device already exists in the list by MAC address
          final existingIndex = _keiserDevices.indexWhere(
            (d) => d['macAddress'] == keiserDevice['macAddress']
          );
          
          if (existingIndex >= 0) {
            // Update existing entry
            _keiserDevices[existingIndex] = keiserDevice;
          } else {
            // Add new entry
            _keiserDevices.add(keiserDevice);
          }
          
          // Sort the list by RSSI (strongest signal first)
          _keiserDevices.sort((a, b) => b['rssi'].compareTo(a['rssi']));
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

  /// Save Selected Keiser M3 Device
  void _saveSelectedKeiserDevice(Map<String, dynamic> keiserDevice) async {
    final navigatorState = Navigator.of(context);
    
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text("Confirm Selection"),
          content: Text(
            "Are you sure you want to save Keiser M3?\n"
            "Name: ${keiserDevice['name']}\n"
            "Equipment ID: ${keiserDevice['equipmentId']}\n"
            "MAC: ${keiserDevice['macAddress']}"
          ),
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
                  // Stop scanning
                  _keiserScanSubscription?.cancel();
                  await FlutterBluePlus.stopScan();

                  // Save all the Keiser device info to the bike
                  await _antService.setDeviceInfo(
                    widget.device, 
                    deviceId: keiserDevice['equipmentId'] ?? 0,
                    deviceName: _deviceName, // Keep the current device name
                    dataSourceType: DataSourceType.keiserM3i,
                    macAddress: keiserDevice['macAddress'],
                  );
                  
                  log.i("Keiser M3 device info saved successfully!");

                  // Navigate back to previous screen after successful save
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Keiser device saved successfully"),
                        duration: Duration(seconds: 1),
                      ),
                    );
                    await Future.delayed(const Duration(milliseconds: 500));
                    navigatorState.pop(); // Return to previous screen
                  }
                } catch (e) {
                  log.e("Failed to save Keiser M3 Device: $e");
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

  /// Set bike type (data source type)
  void _showSetBikeTypeDialog() {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text("Set Bike Type"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text("ANT+ Device"),
                subtitle: const Text("For ANT+ compatible exercise bikes"),
                selected: _dataSourceType == DataSourceType.antDevice,
                onTap: () async {
                  Navigator.pop(dialogContext);
                  await _setBikeType(DataSourceType.antDevice);
                },
              ),
              ListTile(
                title: const Text("Keiser M3i"),
                subtitle: const Text("For Keiser M3i exercise bikes"),
                selected: _dataSourceType == DataSourceType.keiserM3i,
                onTap: () async {
                  Navigator.pop(dialogContext);
                  await _setBikeType(DataSourceType.keiserM3i);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text("Cancel"),
            ),
          ],
        );
      },
    );
  }

  /// Set bike type
  Future<void> _setBikeType(DataSourceType bikeType) async {
    try {
      // Stop any current scanning
      if (bikeType == DataSourceType.antDevice) {
        _keiserScanSubscription?.cancel();
        await FlutterBluePlus.stopScan();
      } else {
        try {
          await _antService.stopAntSearch(widget.device);
        } catch (e) {
          log.e("Error stopping ANT+ search: $e");
        }
      }

      // Set the new bike type
      await _antService.setDeviceInfo(
        widget.device,
        deviceId: int.tryParse(_deviceId) ?? 0,
        deviceName: _deviceName,
        dataSourceType: bikeType,
        macAddress: _macAddress,
      );

      // Update state
      setState(() {
        _dataSourceType = bikeType;
        if (bikeType == DataSourceType.antDevice) {
          _antDevices.clear();
          _startAntSearch();
        } else {
          _keiserDevices.clear();
          _startKeiserSearch();
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Bike type set to ${bikeType.toString()}"),
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (e) {
      log.e("Failed to set bike type: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to set bike type: $e"),
          duration: const Duration(seconds: 2),
        ),
      );
    }
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

            // Check if we've reached the COMPLETED or ABORTED state
            if (progress.state == 'COMPLETED' || progress.state == 'ABORTED') {
              log.i('Firmware update ${progress.state.toLowerCase()}, preparing to return to main screen');
              setState(() {
                _isUpdatingFirmware = false;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Firmware update ${progress.state.toLowerCase()}')),
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
            // Also return to main screen on error after delay
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted) {
                log.i('Attempting to return to main screen after error');
                Navigator.of(context).pop();
                _firmwareUpdateProgressSubscription?.cancel();
              }
            });
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

  // Separate method to handle the async cleanup
  Future<void> _cleanupConnections() async {
    try {
      if (_dataSourceType == DataSourceType.antDevice) {
        _antSearchSubscription?.cancel();
        await _antService.stopAntSearch(widget.device); // ✅ Stop ANT+ scanning first
      } else {
        _keiserScanSubscription?.cancel();
        await FlutterBluePlus.stopScan();
      }
    } catch (e) {
      log.e("Failed to stop scanning: $e");
    }

    log.i("Disconnecting BLE connection...");
    try {
      await _antService.disconnectDevice(widget.device); // ✅ Properly disconnect BLE
    } catch (e) {
      log.e("Failed to disconnect BLE: $e");
    }
  }

  /// Show dialog to edit device name
  void _showEditNameDialog() {
    final TextEditingController nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Device Name'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Device Name',
                helperText: 'Use A-Z, a-z, 0-9 (max 8 characters)',
              ),
              maxLength: 8,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = nameController.text;
              if (!_deviceNameRegex.hasMatch(newName)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invalid name format')),
                );
                return;
              }
              Navigator.pop(context);
              await _updateDeviceName(newName);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  /// Show dialog to edit device ID
  void _showEditDeviceIdDialog() {
    final TextEditingController idController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Device ID'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: idController,
              decoration: const InputDecoration(
                labelText: 'Device ID',
                helperText: 'Enter a number between 0 and 65535',
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newId = int.tryParse(idController.text);
              if (newId == null || newId < 0 || newId > 65535) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invalid ID (must be 0-65535)')),
                );
                return;
              }
              Navigator.pop(context);
              await _updateDeviceId(newId);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  /// Update device name in characteristic 0x1524
  Future<void> _updateDeviceName(String newName) async {
    try {
      await _antService.setDeviceInfo(
        widget.device,
        deviceId: int.tryParse(_deviceId) ?? 0,
        deviceName: newName,
        dataSourceType: _dataSourceType,
        macAddress: _macAddress,
      );
      
      log.i("Device name updated successfully");
      
      // Return to main screen as device will reboot
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const BleScanScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      log.e("Failed to update device name: $e");
      if (mounted) {
        setState(() {
          _updateError = "Failed to update device name: $e";
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_updateError!)),
        );
      }
    }
  }

  /// Update device ID using ANT+ service
  Future<void> _updateDeviceId(int newId) async {
    try {
      // Set device ID - device will reboot after this
      await _antService.saveSelectedAntDevice(widget.device, newId);
    } catch (e) {
      // Even if we get an error (like GATT_ERROR), we should still return to main screen
      // since the device is likely rebooting
      log.i("Device ID update initiated, device is rebooting");
    }
    
    // Always return to main screen since device will reboot
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const BleScanScreen()),
        (route) => false,
      );
    }
  }

  /// Start RSSI updates for the BLE device
  void _startRssiUpdates() {
    _rssiSubscription = Stream.periodic(const Duration(seconds: 2))
      .asyncMap((_) => widget.device.readRssi())
      .listen((rssi) {
        if (mounted) {
          setState(() {
            _bleRssi = rssi;
          });
        }
      }, onError: (e) {
        log.e("Error reading RSSI: $e");
      });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_deviceName),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'edit_name':
                  _showEditNameDialog();
                  break;
                case 'edit_id':
                  _showEditDeviceIdDialog();
                  break;
                case 'set_bike_type':
                  _showSetBikeTypeDialog();
                  break;
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'edit_name',
                child: Text('Edit Device Name'),
              ),
              const PopupMenuItem<String>(
                value: 'edit_id',
                child: Text('Edit Device ID'),
              ),
              const PopupMenuItem<String>(
                value: 'set_bike_type',
                child: Text('Set Bike Type'),
              ),
            ],
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_updateError != null) ...[
              Container(
                padding: const EdgeInsets.all(8.0),
                color: Colors.red[100],
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _updateError!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        setState(() {
                          _updateError = null;
                        });
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            _isFetchingData
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("🔋 Battery: $_batteryStatus", style: const TextStyle(fontSize: 18)),
                      Text("📶 Signal Strength: $_bleRssi dBm", style: const TextStyle(fontSize: 18)),
                      Text("🔢 Current Device ID: $_deviceId", style: const TextStyle(fontSize: 18)),
                      Text("🚲 Bike Type: ${_dataSourceType.toString()}", style: const TextStyle(fontSize: 18)),
                      if (_dataSourceType == DataSourceType.keiserM3i) 
                        Text("📱 MAC Address: $_macAddress", style: const TextStyle(fontSize: 18)),
                      Text("📱 Firmware Version: $_currentFirmwareVersion", style: const TextStyle(fontSize: 18)),
                      Text("🖥 Hardware Version: $_hardwareVersion", style: const TextStyle(fontSize: 18)),
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
              _dataSourceType == DataSourceType.antDevice
                  ? const Text("🔍 Found ANT+ Devices:", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))
                  : const Text("🔍 Found Keiser M3 Devices:", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              Expanded(
                child: _dataSourceType == DataSourceType.antDevice
                    ? _buildAntDevicesList()
                    : _buildKeiserDevicesList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAntDevicesList() {
    return RefreshIndicator(
      onRefresh: () async {
        setState(() {
          _antDevices.clear();
        });
        _startAntSearch();
      },
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
    );
  }

  Widget _buildKeiserDevicesList() {
    return RefreshIndicator(
      onRefresh: () async {
        setState(() {
          _keiserDevices.clear();
        });
        _startKeiserSearch();
      },
      child: _keiserDevices.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _keiserDevices.length,
              itemBuilder: (context, index) {
                final keiserDevice = _keiserDevices[index];
                return ListTile(
                  title: Text("${keiserDevice['name']}"),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("RSSI: ${keiserDevice['rssi']} dBm"),
                      Text("Equipment ID: ${keiserDevice['equipmentId']}"),
                      Text("MAC: ${keiserDevice['macAddress']}"),
                    ],
                  ),
                  isThreeLine: true,
                  trailing: ElevatedButton(
                    onPressed: () => _saveSelectedKeiserDevice(keiserDevice),
                    child: const Text("Select"),
                  ),
                );
              },
            ),
    );
  }
}

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:nordic_dfu/nordic_dfu.dart';

import '../utils/ble_constants.dart';

class DfuProgressState {
  final double progress;
  final String state;
  final String? error;

  DfuProgressState({
    required this.progress,
    required this.state,
    this.error,
  });
}

class DfuService {
  static const String _dfuDeviceName = 'BikeUpdate';
  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 1);
  final _progressController = StreamController<DfuProgressState>.broadcast();

  Stream<DfuProgressState> get progressStream => _progressController.stream;

  Future<void> _startDfu(String filePath, String? macAddress) async {
    if (macAddress == null) {
      _emitError("No MAC address provided");
      return;
    }

    _progressController.add(DfuProgressState(progress: 0, state: 'PREPARING'));

    final handler = DfuEventHandler(
      onDeviceDisconnecting: (address) {
        debugPrint("🔌 Disconnecting from $address");
      },
      onProgressChanged: (address, percent, speed, avgSpeed, currentPart, partsTotal) {
        debugPrint("📶 Progress: $percent%");
        _progressController.add(DfuProgressState(
          progress: percent / 100,
          state: 'UPLOADING',
        ));
      },
      onDfuCompleted: (address) {
        debugPrint("✅ DFU complete for $address");
        _progressController.add(DfuProgressState(
          progress: 1.0,
          state: 'COMPLETED',
        ));
      },
      onError: (address, error, code, type) {
        _emitError("DFU failed: $error");
      },
    );

    try {
      await NordicDfu().startDfu(
        macAddress,
        filePath,
        dfuEventHandler: handler,
        androidParameters: const AndroidParameters(rebootTime: 1000),
        darwinParameters: const DarwinParameters(
          alternativeAdvertisingNameEnabled: true,
        ),
      );
    } catch (e) {
      _emitError("DFU exception: $e");
    }
  }

  Future<void> abortDfu() async {
    try {
      await NordicDfu().abortDfu();
      _progressController.add(DfuProgressState(
        progress: 0,
        state: 'ABORTED',
      ));
    } catch (e) {
      _emitError("Failed to abort DFU: $e");
    }
  }

  void _emitError(String message) {
    debugPrint("❌ $message");
    _progressController.add(DfuProgressState(
      progress: 0,
      state: 'ERROR',
      error: message,
    ));
  }

/// Trigger DFU mode on the device
  Future<void> triggerDfuMode(BluetoothDevice device) async {
    int retryCount = 0;
    while (retryCount < _maxRetries) {
      try {
        print("📡 Triggering DFU mode... (Attempt ${retryCount + 1}/$_maxRetries)");
        
        // Ensure device is connected
        if (!device.isConnected) {
          print("🔌 Device not connected, attempting to connect...");
          await device.connect(timeout: const Duration(seconds: 5));
          await Future.delayed(const Duration(milliseconds: 500)); // Give it time to stabilize
        }

        // Get the custom service and characteristic
        final services = await device.discoverServices();
        final service = services.firstWhere(
          (s) => s.serviceUuid == BleConstants.customService,
          orElse: () => throw Exception('Custom service not found'),
        );
        
        final characteristic = service.characteristics.firstWhere(
          (c) => c.characteristicUuid == BleConstants.scanControlChar,
          orElse: () => throw Exception('Scan control characteristic not found'),
        );

        // Check if characteristic is writable
        if (!characteristic.properties.write) {
          throw Exception('Characteristic is not writable');
        }

        // Send DFU trigger command (0x05)
        await characteristic.write([0x05], withoutResponse: false).catchError((e) {
          if (e.toString().contains('133')) {
            print("⚠️ GATT_ERROR 133 after DFU trigger — expected during reboot");
          } else {
            throw e;
          }
        });

        print("✅ DFU trigger command sent — device may disconnect immediately");
        await device.disconnect();
        await Future.delayed(Duration(seconds: 1)); // Let it reboot
        return;

      } catch (e) {
        retryCount++;
        print("❌ Attempt $retryCount failed: $e");
        
        if (retryCount < _maxRetries) {
          print("⏳ Waiting before retry...");
          await Future.delayed(_retryDelay);
        } else {
          print("❌ All retry attempts failed");
          rethrow;
        }
      }
    }
  }
  
  Future<void> performFullDfu(BluetoothDevice originalDevice, String filePath) async {
    try {

      // 1. Trigger DFU mode on the original device
      _progressController.add(DfuProgressState(
        progress: 0,
        state: 'TRIGGERING_DFU',
      ));
      
      await triggerDfuMode(originalDevice);

      // 2. Start scanning for 'BikeUpdate'
      _progressController.add(DfuProgressState(
        progress: 0,
        state: 'SCANNING_FOR_BOOTLOADER',
      ));
      
      print("🔍 Scanning for DFU bootloader (BikeUpdate)...");
      final completer = Completer<BluetoothDevice>();

      final scanSub = FlutterBluePlus.scanResults.listen((results) {
        for (final result in results) {
          final name = result.device.platformName;
          if (name == _dfuDeviceName) {
            print("✅ Found DFU Bootloader: ${result.device.remoteId.str}");
            completer.complete(result.device);
            break;
          }
        }
      });

      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

      final dfuDevice = await completer.future.timeout(
        const Duration(seconds: 12),
        onTimeout: () {
          FlutterBluePlus.stopScan();
          scanSub.cancel();
          throw Exception("Timeout: DFU device not found");
        },
      );

      await FlutterBluePlus.stopScan();
      await scanSub.cancel();

      // 3. Start DFU with new device MAC
      final macAddress = dfuDevice.remoteId.str;
      await _startDfu(filePath, macAddress);
    } catch (e) {
      _emitError("❌ DFU process failed: $e");
    }
  }

  void dispose() {
    _progressController.close();
  }
}

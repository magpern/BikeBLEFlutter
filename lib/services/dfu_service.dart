import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:nordic_dfu/nordic_dfu.dart';
import '../utils/logger.dart';

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
        log.i("Disconnecting from $address");
      },
      onProgressChanged: (address, percent, speed, avgSpeed, currentPart, partsTotal) {
        log.i("Progress: $percent%");
        log.i("Emitting progress update: ${percent / 100} - UPLOADING");
        _progressController.add(DfuProgressState(
          progress: percent / 100,
          state: 'UPLOADING',
        ));
      },
      onDfuCompleted: (address) {
        log.i("DFU complete for $address");
        log.i("Emitting completion update: 1.0 - COMPLETED");
        _progressController.add(DfuProgressState(
          progress: 1.0,
          state: 'COMPLETED',
        ));
      },
      onError: (address, error, code, type) {
        log.e("DFU error: $error");
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
    log.e(message);
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
        log.i("Triggering DFU mode... (Attempt ${retryCount + 1}/$_maxRetries)");
        
        // Ensure device is connected
        if (!device.isConnected) {
          log.i("Device not connected, attempting to connect...");
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

        await characteristic.write([0x02], withoutResponse: false);
        await Future.delayed(Duration(milliseconds: 300));
        // Send DFU trigger command (0x05)
        await characteristic.write([0x05], withoutResponse: false).catchError((e) {
          if (e.toString().contains('133')) {
            log.w("GATT_ERROR 133 after DFU trigger — expected during reboot");
          } else {
            throw e;
          }
        });

        log.i("DFU trigger command sent — device may disconnect immediately");
        await device.disconnect();
        await Future.delayed(Duration(seconds: 1)); // Let it reboot
        return;

      } catch (e) {
        retryCount++;
        log.e("Attempt $retryCount failed: $e");
        
        if (retryCount < _maxRetries) {
          log.i("Waiting before retry...");
          await Future.delayed(_retryDelay);
        } else {
          log.e("All retry attempts failed");
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
      
      log.i("Scanning for DFU bootloader (BikeUpdate)...");
      final completer = Completer<BluetoothDevice>();

      final scanSub = FlutterBluePlus.scanResults.listen((results) {
        for (final result in results) {
          final name = result.device.platformName;
          if (name == _dfuDeviceName) {
            log.i("Found DFU Bootloader: ${result.device.remoteId.str}");
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

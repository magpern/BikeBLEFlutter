import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

/// UUIDs for BLE services and characteristics used in the project.
class BleConstants {
  // ✅ FTMS Service (Fitness Machine)
  static final Uuid ftmsService = Uuid.parse("00001826-0000-1000-8000-00805f9b34fb");

  // ✅ Custom ANT+ BLE Service (0x1600)
  static final Uuid customService = Uuid.parse("00001600-0000-1000-8000-00805f9b34fb");

  // ✅ Device Information Service (0x180A)
  static final Uuid deviceInfoService = Uuid.parse("0000180a-0000-1000-8000-00805f9b34fb");

  // ✅ Manufacturer Name Characteristic (0x2A29)
  static final Uuid manufacturerChar = Uuid.parse("00002a29-0000-1000-8000-00805f9b34fb");

  // ✅ ANT+ Search Control Characteristic (0x1601)
  static final Uuid scanControlChar = Uuid.parse("00001601-0000-1000-8000-00805f9b34fb");

  // ✅ ANT+ Search Results Characteristic (0x1602)
  static final Uuid scanResultsChar = Uuid.parse("00001602-0000-1000-8000-00805f9b34fb");

  // ✅ ANT+ Device Selection Characteristic (0x1603)
  static final Uuid selectDeviceChar = Uuid.parse("00001603-0000-1000-8000-00805f9b34fb");

  // ✅ Battery Service (0x180F) & Battery Level Characteristic (0x2A19)
  static final Uuid batteryService = Uuid.parse("0000180F-0000-1000-8000-00805f9b34fb");
  static final Uuid batteryLevelChar = Uuid.parse("00002A19-0000-1000-8000-00805f9b34fb");

  // Getters for each UUID
  static Uuid get ftmsServiceUuid => ftmsService;
  static Uuid get customServiceUuid => customService;
  static Uuid get deviceInfoServiceUuid => deviceInfoService;
  static Uuid get manufacturerCharUuid => manufacturerChar;
  static Uuid get scanControlCharUuid => scanControlChar;
  static Uuid get scanResultsCharUuid => scanResultsChar;
  static Uuid get selectDeviceCharUuid => selectDeviceChar;
  static Uuid get batteryServiceUuid => batteryService;
  static Uuid get batteryLevelCharUuid => batteryLevelChar;
}

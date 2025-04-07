import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// UUIDs for BLE services and characteristics used in the project.
class BleConstants {
  // FTMS Service (Fitness Machine)
  static final Guid ftmsService = Guid("00001826-0000-1000-8000-00805f9b34fb");

  // Cycling Power Service
  static final Guid cyclingPowerService = Guid("00001818-0000-1000-8000-00805f9b34fb");

  // Custom ANT+ BLE Service (0x1600)
  static final Guid customService = Guid("00001600-0000-1000-8000-00805f9b34fb");

  // Device Information Service (0x180A)
  static final Guid deviceInfoService = Guid("0000180a-0000-1000-8000-00805f9b34fb");

  // Manufacturer Name Characteristic (0x2A29)
  static final Guid manufacturerChar = Guid("00002a29-0000-1000-8000-00805f9b34fb");

  // ANT+ Search Control Characteristic (0x1601)
  static final Guid scanControlChar = Guid("00001601-0000-1000-8000-00805f9b34fb");

  // ANT+ Search Results Characteristic (0x1602)
  static final Guid scanResultsChar = Guid("00001602-0000-1000-8000-00805f9b34fb");

  // ANT+ Device Selection Characteristic (0x1603)
  static final Guid selectDeviceChar = Guid("00001603-0000-1000-8000-00805f9b34fb");

  // Battery Service (0x180F)
  static final Guid batteryService = Guid("0000180F-0000-1000-8000-00805f9b34fb");

  // Battery Level Characteristic (0x2A19)
  static final Guid batteryLevelChar = Guid("00002A19-0000-1000-8000-00805f9b34fb");

  // Firmware Version Characteristic (0x1604)
  static final Guid firmwareVersionChar = Guid("00001604-0000-1000-8000-00805f9b34fb");

  // Firmware Update Characteristic (0x1605)
  static final Guid firmwareUpdateChar = Guid("00001605-0000-1000-8000-00805f9b34fb");

  // Firmware Revision String Characteristic (0x2A26)
  static final Guid firmwareRevisionChar = Guid("00002A26-0000-1000-8000-00805f9b34fb");

  // Getters for each UUID
  static Guid get ftmsServiceUuid => ftmsService;
  static Guid get cyclingPowerServiceUuid => cyclingPowerService;
  static Guid get customServiceUuid => customService;
  static Guid get deviceInfoServiceUuid => deviceInfoService;
  static Guid get manufacturerCharUuid => manufacturerChar;
  static Guid get scanControlCharUuid => scanControlChar;
  static Guid get scanResultsCharUuid => scanResultsChar;
  static Guid get selectDeviceCharUuid => selectDeviceChar;
  static Guid get batteryServiceUuid => batteryService;
  static Guid get batteryLevelCharUuid => batteryLevelChar;
  static Guid get firmwareVersionCharUuid => firmwareVersionChar;
  static Guid get firmwareUpdateCharUuid => firmwareUpdateChar;
  static Guid get firmwareRevisionCharUuid => firmwareRevisionChar;
}

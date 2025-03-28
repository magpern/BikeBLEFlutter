import 'package:logger/logger.dart';

// Create a logger instance with custom configuration
final log = Logger(
  printer: PrettyPrinter(
    methodCount: 0,
    errorMethodCount: 8,
    lineLength: 120,
    colors: true,
    printEmojis: true,
    printTime: true,
  ),
  // In release mode, only show errors
  level: const bool.fromEnvironment('dart.vm.product') ? Level.error : Level.debug,
); 
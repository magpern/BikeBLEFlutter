import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart' show PackageInfo;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_file/open_file.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/logger.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

// A global navigator key to use for dialogs
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class UpdateService {
  static const String _baseUrl = 'https://api.github.com/repos/magpern/BikeBLEFlutter/releases/latest';
  
  // Callback for when an APK file is downloaded
  Function(File)? _onApkDownloaded;
  
  /// Set a callback for when update APK is downloaded
  void setPendingUpdateCallback(Function(File) callback) {
    _onApkDownloaded = callback;
  }
  
  /// Check for updates and return update info
  Future<Map<String, dynamic>> checkForUpdates(BuildContext context) async {
    try {
      // Get current app version
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      log.i("Current app version: $currentVersion");
      
      // Get latest release from GitHub
      final response = await http.get(Uri.parse(_baseUrl));
      if (response.statusCode != 200) {
        return {
          'hasUpdate': false,
          'error': 'Failed to fetch release info: HTTP ${response.statusCode}'
        };
      }
      
      final data = json.decode(response.body);
      final latestVersion = data['tag_name'].toString().replaceFirst('v', '');
      log.i("Latest GitHub version: $latestVersion");
      
      // Find APK asset
      final assets = data['assets'] as List;
      final apkAsset = assets.firstWhere(
        (asset) => asset['name'].toString().endsWith('.apk'),
        orElse: () => null
      );
      
      if (apkAsset == null) {
        return {
          'hasUpdate': false,
          'error': 'No APK file found in the latest release'
        };
      }
      
      // Compare versions
      bool hasUpdate = _isNewerVersion(currentVersion, latestVersion);
      
      if (hasUpdate) {
        log.i("Update available: $latestVersion");
        return {
          'hasUpdate': true,
          'currentVersion': currentVersion,
          'latestVersion': latestVersion,
          'releaseNotes': data['body'],
          'downloadUrl': apkAsset['browser_download_url'],
          'publishedAt': data['published_at']
        };
      } else {
        log.i("App is up to date");
        return {
          'hasUpdate': false
        };
      }
    } catch (e) {
      log.e("Error checking for updates: $e");
      return {
        'hasUpdate': false,
        'error': e.toString()
      };
    }
  }
  
  /// Compare semantic versions and return true if version2 is newer than version1
  bool _isNewerVersion(String version1, String version2) {
    // Remove any 'v' prefix
    version1 = version1.replaceFirst('v', '');
    version2 = version2.replaceFirst('v', '');
    
    try {
      // Split versions into segments
      List<String> v1Parts = version1.split('.');
      List<String> v2Parts = version2.split('.');
      
      // Ensure both version arrays have at least 3 parts (major.minor.patch)
      while (v1Parts.length < 3) v1Parts.add('0');
      while (v2Parts.length < 3) v2Parts.add('0');
      
      // Compare major version
      int v1Major = int.parse(v1Parts[0]);
      int v2Major = int.parse(v2Parts[0]);
      if (v2Major > v1Major) return true;
      if (v2Major < v1Major) return false;
      
      // Compare minor version
      int v1Minor = int.parse(v1Parts[1]);
      int v2Minor = int.parse(v2Parts[1]);
      if (v2Minor > v1Minor) return true;
      if (v2Minor < v1Minor) return false;
      
      // Compare patch version
      int v1Patch = int.parse(v1Parts[2]);
      int v2Patch = int.parse(v2Parts[2]);
      if (v2Patch > v1Patch) return true;
      
      // Handle build/pre-release versions if needed
      if (v1Parts.length > 3 && v2Parts.length > 3) {
        // If there are pre-release identifiers, compare them
        return v2Parts[3].compareTo(v1Parts[3]) > 0;
      }
      
      return false;
    } catch (e) {
      log.e("Error comparing versions: $e");
      return false;
    }
  }
  
  /// Show update dialog to the user
  void showUpdateDialog(BuildContext context, Map<String, dynamic> updateInfo) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Update Available'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A new version (${updateInfo['latestVersion']}) is available.',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('Release Notes:'),
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  updateInfo['releaseNotes'] ?? 'No release notes available',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _downloadAndInstallUpdate(context, updateInfo['downloadUrl']);
            },
            child: const Text('Update Now'),
          ),
        ],
      ),
    );
  }
  
  /// Download and install the update
  Future<void> _downloadAndInstallUpdate(BuildContext context, String downloadUrl) async {
    // Use a flag to track if dialog is shown
    bool isProgressDialogShowing = false;
    BuildContext? dialogContext;
    final progressController = StreamController<double>();
    File? downloadedFile;
    
    try {
      bool permissionGranted = false;
      
      // Check Android version and request appropriate permissions
      if (Platform.isAndroid) {
        // For Android 13+ (API level 33+)
        if (await _isAndroid13OrHigher()) {
          // Request the new storage permissions introduced in Android 13
          final storageStatus = await Permission.photos.request();
          permissionGranted = storageStatus.isGranted;
        } else {
          // For Android 12 and below
          final storageStatus = await Permission.storage.request();
          permissionGranted = storageStatus.isGranted;
        }
        
        // Always need install permission for APK
        final installStatus = await Permission.requestInstallPackages.request();
        if (!installStatus.isGranted) {
          log.e("Install permission denied");
          if (navigatorKey.currentContext != null) {
            _showErrorSnackBar(navigatorKey.currentContext!, "Permission to install packages is required for updates");
          }
          return;
        }
      } else {
        // For non-Android platforms
        permissionGranted = true;
      }
      
      if (!permissionGranted) {
        log.e("Storage permission denied");
        if (navigatorKey.currentContext != null) {
          _showErrorSnackBar(navigatorKey.currentContext!, "Storage permission is required to download the update");
        }
        return;
      }
      
      // Show download progress dialog with progress indicator - always use navigator key
      if (navigatorKey.currentContext != null) {
        isProgressDialogShowing = true;
        showDialog(
          context: navigatorKey.currentContext!,
          barrierDismissible: false,
          builder: (BuildContext ctx) {
            dialogContext = ctx;
            return _buildProgressDialog(ctx, progressController.stream);
          },
        );
      } else {
        log.e("No valid context found for showing progress dialog");
        return;
      }
      
      // Get temporary directory
      final directory = await getExternalStorageDirectory() ?? await getTemporaryDirectory();
      final filePath = '${directory.path}/update.apk';
      log.i("Downloading APK to: $filePath");
      
      // Create output file
      downloadedFile = File(filePath);
      if (await downloadedFile.exists()) {
        await downloadedFile.delete();
      }
      
      // Download with progress tracking
      final httpClient = http.Client();
      final request = http.Request('GET', Uri.parse(downloadUrl));
      final response = await httpClient.send(request);
      
      final totalBytes = response.contentLength ?? 0;
      int receivedBytes = 0;
      
      final fileStream = downloadedFile.openWrite();
      
      await response.stream.forEach((chunk) {
        receivedBytes += chunk.length;
        fileStream.add(chunk);
        if (totalBytes > 0) {
          final progress = receivedBytes / totalBytes;
          progressController.add(progress);
        }
      });
      
      await fileStream.flush();
      await fileStream.close();
      
      // Close progress dialog if it's showing
      _closeProgressDialog(dialogContext);
      isProgressDialogShowing = false;
      
      if (Platform.isAndroid) {
        log.i("Attempting to install APK: $filePath");
        
        // Try to install APK
        await _installApk(downloadedFile);
      } else {
        // For other platforms, just launch the download URL
        _launchUrl(downloadUrl);
      }
    } catch (e) {
      log.e("Error downloading update: $e");
      
      // Close progress dialog if it's showing
      _closeProgressDialog(dialogContext);
      
      // Show error if a valid context is available
      if (navigatorKey.currentContext != null) {
        _showErrorSnackBar(navigatorKey.currentContext!, "Failed to download update: $e");
      }
    } finally {
      await progressController.close();
    }
  }
  
  /// Close progress dialog safely
  void _closeProgressDialog(BuildContext? dialogContext) {
    if (dialogContext != null) {
      try {
        Navigator.of(dialogContext, rootNavigator: true).pop();
      } catch (e) {
        log.e("Error closing dialog: $e");
        // Dialog may have been closed already, ignore
      }
    }
  }
  
  /// Install APK file
  Future<void> _installApk(File apkFile) async {
    try {
      if (!await apkFile.exists()) {
        log.e("APK file doesn't exist at ${apkFile.path}");
        return;
      }
      
      // Notify callback about the downloaded APK file
      if (_onApkDownloaded != null) {
        _onApkDownloaded!(apkFile);
      }
      
      // Method 1: Use OpenFile plugin (most reliable)
      final result = await OpenFile.open(apkFile.path);
      if (result.type != ResultType.done) {
        log.e("Failed to install APK using OpenFile: ${result.message}");
        
        // If OpenFile fails, try other methods
        if (navigatorKey.currentContext != null) {
          // Show a dialog asking user to install manually
          showDialog(
            context: navigatorKey.currentContext!,
            builder: (context) => AlertDialog(
              title: const Text("Manual Installation Required"),
              content: const Text(
                "The automatic installation couldn't be completed. Would you like to install the update manually?"
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _launchUrl("content://${apkFile.path}");
                  },
                  child: const Text("Install Manually"),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      log.e("Error installing APK: $e");
      // If all else fails, at least log the error
      if (navigatorKey.currentContext != null) {
        _showErrorSnackBar(navigatorKey.currentContext!, "Failed to install update: $e");
      }
    }
  }
  
  /// Show error message as SnackBar
  void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }
  
  /// Build a progress dialog for showing download progress
  Widget _buildProgressDialog(BuildContext context, [Stream<double>? progressStream]) {
    return AlertDialog(
      title: const Text('Downloading Update'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (progressStream != null)
            StreamBuilder<double>(
              stream: progressStream,
              builder: (context, snapshot) {
                final progress = snapshot.data ?? 0.0;
                return Column(
                  children: [
                    LinearProgressIndicator(value: progress),
                    const SizedBox(height: 8),
                    Text('${(progress * 100).toStringAsFixed(0)}%'),
                  ],
                );
              },
            )
          else
            const CircularProgressIndicator(),
          const SizedBox(height: 16),
          const Text('Please wait while the update is downloaded...'),
        ],
      ),
    );
  }
  
  /// Launch a URL
  Future<void> _launchUrl(String url) async {
    if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
      log.e('Could not launch $url');
    }
  }
  
  /// Check if device is running Android 13 or higher
  Future<bool> _isAndroid13OrHigher() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      return androidInfo.version.sdkInt >= 33; // Android 13 is API level 33
    }
    return false;
  }
} 
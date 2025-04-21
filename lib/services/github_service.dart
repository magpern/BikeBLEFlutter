import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/logger.dart';

class GitHubService {
  static const String _baseUrl = 'https://api.github.com';
  static const String _repoOwner = 'magpern';
  static const String _repoName = 'Bike2FTMS';

  /// Compare two version strings
  /// Returns true if version2 is newer than version1
  bool isNewerVersion(String version1, String version2) {
    // Remove 'v' prefix if present
    version1 = version1.replaceFirst('v', '');
    version2 = version2.replaceFirst('v', '');

    try {
      // Split into base version and suffix
      final v1Parts = version1.split('-');
      final v2Parts = version2.split('-');
      
      // Compare base versions (x.y.z)
      final v1Base = v1Parts[0];
      final v2Base = v2Parts[0];
      
      List<int> v1 = v1Base.split('.').map(int.parse).toList();
      List<int> v2 = v2Base.split('.').map(int.parse).toList();

      // Compare major.minor.patch numbers
      for (int i = 0; i < 3; i++) {
        if (v2[i] > v1[i]) return true;
        if (v2[i] < v1[i]) return false;
      }

      // If base versions are equal, compare suffixes
      if (v1Parts.length > 1 && v2Parts.length > 1) {
        final v1Suffix = v1Parts[1];
        final v2Suffix = v2Parts[1];
        
        // If one is snapshot and other is sha, consider sha as newer
        if (v1Suffix == 'snapshot' && v2Suffix != 'snapshot') return true;
        if (v2Suffix == 'snapshot' && v1Suffix != 'snapshot') return false;
        
        // If both are sha numbers, compare them
        if (v1Suffix != 'snapshot' && v2Suffix != 'snapshot') {
          return v2Suffix.compareTo(v1Suffix) > 0;
        }
      }
      
      // If one has suffix and other doesn't, consider the one with suffix as newer
      if (v1Parts.length > 1 && v2Parts.length == 1) return true;
      if (v2Parts.length > 1 && v1Parts.length == 1) return false;
      
      return false;
    } catch (e) {
      log.e('Version comparison error: $e');
      return false;
    }
  }

  /// Fetch latest release information from GitHub
  Future<Map<String, dynamic>> getLatestRelease({String? hardwareVersion}) async {
    try {
      log.i("Fetching latest release, hardware version: ${hardwareVersion ?? 'not specified'}");
      
      final response = await http.get(
        Uri.parse('$_baseUrl/repos/$_repoOwner/$_repoName/releases/latest'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final version = data['tag_name'] as String;
        log.i("Found latest release: $version");
        
        // Find the zip asset matching the hardware version if specified
        final assets = data['assets'] as List;
        log.i("Found ${assets.length} assets in release");
        
        // Log all available assets for debugging
        for (var asset in assets) {
          log.d("Available asset: ${asset['name']}");
        }
        
        Map<String, dynamic>? matchingAsset;
        
        if (hardwareVersion != null) {
          // Extract hardware identifier from Rev_ prefix (e.g., "Rev_promicro" -> "promicro")
          String hardwareId = "";
          final revPrefix = "Rev_";
          if (hardwareVersion.startsWith(revPrefix)) {
            hardwareId = hardwareVersion.substring(revPrefix.length).toLowerCase();
            log.i("Extracted hardware ID: $hardwareId from $hardwareVersion");
          } else {
            hardwareId = hardwareVersion.toLowerCase();
            log.i("Using hardware version as ID: $hardwareId");
          }
          
          if (hardwareId.isNotEmpty) {
            log.i("Looking for asset containing: $hardwareId");
            // Look for a specific asset with the hardware ID in its name (case insensitive)
            for (var asset in assets) {
              final assetName = asset['name'].toString().toLowerCase();
              if (assetName.contains(hardwareId) && assetName.endsWith('.zip')) {
                matchingAsset = asset;
                log.i("✅ Found matching asset: ${asset['name']}");
                break;
              }
            }
            
            if (matchingAsset == null) {
              log.w("❌ No matching asset found for hardware ID: $hardwareId");
              return {
                'version': version,
                'downloadUrl': null,
                'success': false,
                'error': 'No firmware found for hardware: $hardwareVersion',
              };
            }
          }
        } else {
          // If no hardware version specified, fall back to the first zip asset
          log.i("No hardware version specified, looking for any ZIP asset");
          for (var asset in assets) {
            if (asset['name'].toString().toLowerCase().endsWith('.zip')) {
              matchingAsset = asset;
              log.i("Using generic asset: ${asset['name']}");
              break;
            }
          }
        }
        
        // If no hardware-specific asset found or no hardware version specified,
        // NO LONGER falling back to the first zip asset
        if (matchingAsset == null) {
          log.e("No suitable firmware ZIP found in the release");
          return {
            'version': version,
            'downloadUrl': null,
            'success': false,
            'error': 'No firmware ZIP found in this release',
          };
        }

        // At this point matchingAsset is guaranteed to be non-null
        log.i("Selected asset for download: ${matchingAsset['name']}");
        return {
          'version': version,
          'downloadUrl': matchingAsset['browser_download_url'] as String,
          'assetName': matchingAsset['name'],
          'success': true,
        };
      }

      return {
        'version': 'Unknown',
        'downloadUrl': null,
        'success': false,
        'error': 'Failed to fetch release information',
      };
    } catch (e) {
      log.e('Error fetching GitHub release: $e');
      return {
        'version': 'Unknown',
        'downloadUrl': null,
        'success': false,
        'error': e.toString(),
      };
    }
  }
} 
import 'dart:convert';
import 'package:http/http.dart' as http;

class GitHubService {
  static const String _baseUrl = 'https://api.github.com';
  static const String _repoOwner = 'magpern';
  static const String _repoName = 'Bike2FTMS';

  /// Compare two version strings (e.g., "1.2.3" and "1.2.4")
  /// Returns true if version2 is newer than version1
  bool isNewerVersion(String version1, String version2) {
    // Remove 'v' prefix if present
    version1 = version1.replaceFirst('v', '');
    version2 = version2.replaceFirst('v', '');

    List<int> v1 = version1.split('.').map(int.parse).toList();
    List<int> v2 = version2.split('.').map(int.parse).toList();

    for (int i = 0; i < 3; i++) {
      if (v2[i] > v1[i]) return true;
      if (v2[i] < v1[i]) return false;
    }
    return false;
  }

  /// Fetch latest release information from GitHub
  Future<Map<String, dynamic>> getLatestRelease() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/repos/$_repoOwner/$_repoName/releases/latest'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final version = data['tag_name'] as String;
        
        // Find the first asset with .zip extension
        final assets = data['assets'] as List;
        final zipAsset = assets.firstWhere(
          (asset) => asset['name'].toString().endsWith('.zip'),
          orElse: () => null,
        );

        if (zipAsset != null) {
          return {
            'version': version,
            'downloadUrl': zipAsset['browser_download_url'] as String,
            'success': true,
          };
        }
      }

      return {
        'version': 'Unknown',
        'downloadUrl': null,
        'success': false,
        'error': 'Failed to fetch release information',
      };
    } catch (e) {
      print('❌ Error fetching GitHub release: $e');
      return {
        'version': 'Unknown',
        'downloadUrl': null,
        'success': false,
        'error': e.toString(),
      };
    }
  }
} 
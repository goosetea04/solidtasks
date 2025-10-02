import 'package:flutter/material.dart';
import 'package:solidpod/solidpod.dart';

class AuthService {
  // Get the current authenticated user's WebID using the solidpod library
  static Future<String?> getCurrentUserWebId() async {
    try {
      // Use the actual solidpod getWebId function
      final webId = await getWebId();
      if (webId != null && webId.isNotEmpty) {
        debugPrint('Got WebID from solidpod: $webId');
        return webId;
      } 
      
      debugPrint('No WebID found - user may not be authenticated');
      return null;
    } catch (e) {
      debugPrint('Error getting current user WebID: $e');
      return null;
    }
  }

  /// Check if user is currently authenticated by attempting to get WebID
  static Future<bool> isAuthenticated() async {
    try {
      final webId = await getWebId();
      return webId != null && webId.isNotEmpty;
    } catch (e) {
      debugPrint('Authentication check failed: $e');
      return false;
    }
  }

  /// Validate that a WebID is properly formatted
  static bool isValidWebId(String? webId) {
    if (webId == null || webId.isEmpty) return false;
    
    try {
      final uri = Uri.parse(webId);
      return uri.hasScheme && 
             (uri.scheme == 'https' || uri.scheme == 'http') &&
             uri.hasAuthority &&
             uri.fragment != null; 
    } catch (e) {
      return false;
    }
  }

  /// Extract display name from WebID
  static String getDisplayNameFromWebId(String webId) {
    try {
      final uri = Uri.parse(webId);
      final host = uri.host;
      final parts = host.split('.');
      if (parts.isNotEmpty) {
        return parts.first.replaceAll('-', ' ').replaceAll('_', ' ');
      }
    } catch (e) {
      debugPrint('Error extracting name from WebID: $e');
    }
    return webId;
  }
}

// UI Helper functions for WebID management
class WebIdDialogs {
  // Prompt user for their WebID (fallback if getWebId() fails)
  static Future<String?> promptForWebId(BuildContext context) async {
    final controller = TextEditingController();
    
    final webId = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter Your WebID'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Please enter your WebID to enable sharing:'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'WebID',
                hintText: 'https://pods.acp.solidcommunity.au/profile/card#me',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final input = controller.text.trim();
              if (AuthService.isValidWebId(input)) {
                Navigator.pop(context, input);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a valid WebID'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
    
    return webId;
  }
}
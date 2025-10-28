import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:solidpod/solidpod.dart';

/// Shared utilities for Solid Pod operations
class PodUtils {
  // ============================================================================
  // CONSTANTS
  // ============================================================================
  
  /// Profile card suffix for WebIDs
  static const String profCard = '/profile/card#me';
  
  /// Tasks directory path (relative to user's pod root)
  static const String tasksDirRel = '/solidtasks/data/';
  
  /// Permission logs directory path (relative to user's pod root)
  static const String logsDirRel = '/solidtasks/logs/';
  
  /// Legacy tasks filename (for backward compatibility)
  static const String legacyTasksFile = 'tasks.ttl';
  
  /// Permission log filename
  static const String permLogFile = 'permissions-log.ttl';
  
  /// Task file prefix and extension
  static const String taskPrefix = 'task_';
  static const String taskExt = '.ttl';
  
  // WEBID OPERATIONS

  /// Normalize WebID to ensure consistent format across all services
  /// This ensures WebID comparisons work correctly and prevents duplicate logs.
  static String normalizeWebId(String webId) {
    // Remove profile card suffix if present
    String normalized = webId.replaceAll(profCard, '');
    
    // Ensure trailing slash for base URL
    if (!normalized.endsWith('/')) {
      normalized += '/';
    }
    
    // Add back profile card (remove leading slash from profCard constant)
    return '$normalized${profCard.substring(1)}';
  }
  
  /// Get current user's WebID without the profile card suffix
  static Future<String> getCurrentWebIdClean() async {
    final raw = await getWebId();
    if (raw == null || raw.isEmpty) {
      throw Exception("User is not logged in or WebID unavailable");
    }
    return raw.replaceAll(profCard, '');
  }
  
  /// Get current user's full WebID (with profile card)
  static Future<String> getCurrentWebIdFull() async {
    final raw = await getWebId();
    if (raw == null || raw.isEmpty) {
      throw Exception("User is not logged in or WebID unavailable");
    }
    return raw;
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
  
  // ============================================================================
  // RESOURCE OPERATIONS
  // ============================================================================
  
  /// Check if a resource exists in the Pod
  /// 
  /// [resourceUrl] - Full URL of the resource to check
  /// [isFile] - true for files, false for containers/directories
  /// 
  /// Returns: true if resource exists (200/204), false otherwise
  static Future<bool> checkResourceExists(
    String resourceUrl, {
    bool isFile = true,
  }) async {
    try {
      debugPrint('Checking resource: $resourceUrl');
      final (:accessToken, :dPopToken) = 
          await getTokensForResource(resourceUrl, 'GET');
      
      final response = await http.get(
        Uri.parse(resourceUrl),
        headers: <String, String>{
          'Accept': isFile ? 'text/turtle' : 'text/turtle',
          'Authorization': 'DPoP $accessToken',
          'Link': isFile
              ? '<http://www.w3.org/ns/ldp#Resource>; rel="type"'
              : '<http://www.w3.org/ns/ldp#BasicContainer>; rel="type"',
          'DPoP': dPopToken,
        },
      );
      
      final exists = response.statusCode == 200 || response.statusCode == 204;
      debugPrint('Resource exists: $exists (${response.statusCode})');
      return exists;
      
    } catch (e) {
      debugPrint('Error checking resource: $e');
      return false;
    }
  }
  
  /// Delete a resource from the Pod
  static Future<void> deleteResource(String resourceUrl) async {
    try {
      final (:accessToken, :dPopToken) = 
          await getTokensForResource(resourceUrl, 'DELETE');
      
      final response = await http.delete(
        Uri.parse(resourceUrl),
        headers: {
          'Authorization': 'DPoP $accessToken',
          'DPoP': dPopToken,
        },
      );
      
      // 200/204/205 = success, 404 = already gone (also success)
      if (![200, 204, 205, 404].contains(response.statusCode)) {
        debugPrint('Delete failed: ${response.statusCode} ${response.body}');
        throw Exception('Failed to delete resource: ${response.statusCode}');
      }
      
      debugPrint('Resource deleted: $resourceUrl');
      
    } catch (e) {
      debugPrint('Error deleting resource: $e');
      rethrow;
    }
  }
  
  /// Read Turtle content from a resource
  static Future<String?> readTurtleContent(String resourceUrl) async {
    try {
      final (:accessToken, :dPopToken) = 
          await getTokensForResource(resourceUrl, 'GET');
      
      final response = await http.get(
        Uri.parse(resourceUrl),
        headers: {
          'Accept': 'text/turtle',
          'Authorization': 'DPoP $accessToken',
          'DPoP': dPopToken,
        },
      );
      
      if (response.statusCode == 200) {
        return response.body;
      } else {
        debugPrint('GET $resourceUrl failed: ${response.statusCode}');
        return null;
      }
      
    } catch (e) {
      debugPrint('Error reading Turtle content: $e');
      return null;
    }
  }
  
  // ============================================================================
  // DIRECTORY OPERATIONS
  // ============================================================================
  
  /// Ensure a directory exists, creating it if necessary
  static Future<void> ensureDirectoryExists(String dirPath) async {
    try {
      // Normalize directory path (ensure trailing slash)
      final normalizedPath = dirPath.endsWith('/') ? dirPath : '$dirPath/';
      
      // Check if directory already exists
      final exists = await checkResourceExists(normalizedPath, isFile: false);
      
      if (!exists) {
        debugPrint('Creating directory: $normalizedPath');
        await createDirectory(normalizedPath);
      } else {
        debugPrint('Directory already exists: $normalizedPath');
      }
      
    } catch (e) {
      debugPrint('Error ensuring directory exists: $e');
      rethrow;
    }
  }
  
  /// Create a directory in the Pod
  static Future<void> createDirectory(String dirPath) async {
    try {
      if (!dirPath.endsWith('/')) {
        throw ArgumentError('Directory path must end with /');
      }
      
      final (:accessToken, :dPopToken) = 
          await getTokensForResource(dirPath, 'PUT');
      
      final response = await http.put(
        Uri.parse(dirPath),
        headers: <String, String>{
          'Content-Type': 'text/turtle',
          'Authorization': 'DPoP $accessToken',
          'Link': '<http://www.w3.org/ns/ldp#BasicContainer>; rel="type"',
          'DPoP': dPopToken,
        },
        body: '''@prefix ldp: <http://www.w3.org/ns/ldp#> .
<> a ldp:BasicContainer .
''',
      );
      
      if (![201, 204].contains(response.statusCode)) {
        debugPrint('Create directory failed: ${response.statusCode} ${response.body}');
        throw Exception('Failed to create directory: ${response.statusCode}');
      }
      
      debugPrint('Directory created: $dirPath');
      
    } catch (e) {
      debugPrint('Error creating directory: $e');
      rethrow;
    }
  }
  
  /// List Turtle files in a container/directory
  static Future<List<String>> listTurtleFiles(String containerUrl) async {
    try {
      final (:accessToken, :dPopToken) = 
          await getTokensForResource(containerUrl, 'GET');
      
      final response = await http.get(
        Uri.parse(containerUrl),
        headers: <String, String>{
          'Accept': 'text/turtle',
          'Authorization': 'DPoP $accessToken',
          'Link': '<http://www.w3.org/ns/ldp#BasicContainer>; rel="type"',
          'DPoP': dPopToken,
        },
      );
      
      if (response.statusCode != 200) {
        debugPrint('List container failed: ${response.statusCode}');
        return [];
      }
      
      // Parse Turtle response to extract .ttl file references
      final body = response.body;
      final filePattern = RegExp(r'<([^>]+\.ttl)>');
      final matches = filePattern.allMatches(body);
      
      final files = <String>{};
      for (final match in matches) {
        final url = match.group(1)!;
        // Extract just the filename from the URL
        final filename = Uri.parse(url).pathSegments.last;
        files.add(filename);
      }
      
      debugPrint('Found ${files.length} Turtle files in $containerUrl');
      return files.toList();
      
    } catch (e) {
      debugPrint('Error listing container: $e');
      return [];
    }
  }
  // SPARQL UPDATE OPERATIONS
  
  /// Execute a SPARQL UPDATE query on a resource
  /// Used for inserting/deleting RDF triples without replacing entire file
  static Future<void> executeSparqlUpdate(
    String resourceUrl,
    String sparqlQuery,
  ) async {
    try {
      final (:accessToken, :dPopToken) = 
          await getTokensForResource(resourceUrl, 'PATCH');
      
      final response = await http.patch(
        Uri.parse(resourceUrl),
        headers: {
          'Content-Type': 'application/sparql-update',
          'Authorization': 'DPoP $accessToken',
          'DPoP': dPopToken,
        },
        body: sparqlQuery,
      );
      
      if (![200, 201, 204, 205].contains(response.statusCode)) {
        debugPrint('SPARQL update failed: ${response.statusCode} ${response.body}');
        throw Exception('SPARQL update failed: ${response.statusCode}');
      }
      
      debugPrint('SPARQL update successful on $resourceUrl');
      
    } catch (e) {
      debugPrint('Error executing SPARQL update: $e');
      rethrow;
    }
  }
  // URL HELPERS
  
  /// Build a full resource URL from a WebID and relative path
  static String buildResourceUrl(String webId, String relativePath) {
    final cleanWebId = webId.replaceAll(profCard, '');
    final normalizedPath = relativePath.startsWith('/') 
        ? relativePath.substring(1) 
        : relativePath;
    return '$cleanWebId$normalizedPath';
  }
  
  /// Extract the parent directory URL from a resource URL
  static String getParentDirectory(String resourceUrl) {
    if (resourceUrl.endsWith('/')) {
      // Already a directory, get parent
      final withoutTrailing = resourceUrl.substring(0, resourceUrl.length - 1);
      return withoutTrailing.substring(0, withoutTrailing.lastIndexOf('/') + 1);
    } else {
      // File, get containing directory
      return resourceUrl.substring(0, resourceUrl.lastIndexOf('/') + 1);
    }
  }
  
  /// Extract filename from a resource URL
  static String getFileName(String resourceUrl) {
    final uri = Uri.parse(resourceUrl);
    return uri.pathSegments.last;
  }
  
  // TASK-SPECIFIC HELPERS
  
  /// Generate filename for a task based on its ID
    return '$taskPrefix$taskId$taskExt';
  }
  
  /// Build full task file URL for current user
  static Future<String> taskFileUrl(String taskId) async {
    final webId = await getCurrentWebIdClean();
    return '$webId$tasksDirRel${taskFileName(taskId)}';
  }
  
  /// Check if a filename is a task file
  static bool isTaskFile(String filename) {
    return filename.startsWith(taskPrefix) && filename.endsWith(taskExt);
  }
  
  // NAMESPACE HELPERS (for permission logs)
  
  /// Generate log namespace URI based on user's WebID
  static String getLogNamespace(String webId) {
    final cleanWebId = webId.replaceAll(profCard, '');
    return '${cleanWebId}log#';
  }
  
  /// Generate data namespace URI based on user's WebID
  static String getDataNamespace(String webId) {
    final cleanWebId = webId.replaceAll(profCard, '');
    return '${cleanWebId}data#';
  }
  
  /// Get permission log file URL for a user
  static String getPermissionLogUrl(String webId) {
    final cleanWebId = webId.replaceAll(profCard, '');
    return '$cleanWebId$logsDirRel$permLogFile';
  }
}
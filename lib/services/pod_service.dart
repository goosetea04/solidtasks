import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:solidpod/solidpod.dart';
import '../models/task.dart';
import '../main.dart'; 
import 'pod_service_acp.dart';
import 'permission_log_service.dart';

class PodService {
  static const String profCard = '/profile/card#me';
  // Directory stays the same
  static const String tasksDirRel = '/solidtasks/data/';
  // Kept for backward compatibility (legacy combined file)
  static const String legacyTasksFile = 'tasks.ttl';
  static const String updateTimeLabel = 'lastUpdated';
  static const String _taskPrefix = 'task_';
  static const String _taskExt = '.ttl';

  static Future<void> openShareUiForTask(
    BuildContext context,
    StatefulWidget returnTo,
    String taskId,
  ) async {
    final fileName = _fileNameForTask(taskId); 
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GrantPermissionUi(
          fileName: fileName, // limit UI to just this task file
          child: returnTo,    // where to return after the UI
        ),
      ),
    );
  }

  static Future<void> deleteTaskFile(String taskUrl) async {
    // Get tokens using the same pattern as other methods
    final (:accessToken, :dPopToken) = await getTokensForResource(taskUrl, 'DELETE');
    
    final response = await http.delete(
      Uri.parse(taskUrl),
      headers: {
        'Authorization': 'DPoP $accessToken',  // Use DPoP, not Bearer
        'DPoP': dPopToken,
      },
    );
    
    if (response.statusCode != 200 && response.statusCode != 204) {
      debugPrint('Failed to delete task file: ${response.statusCode} ${response.body}');
      throw Exception('Failed to delete task file: ${response.statusCode}');
    }
    
    debugPrint('Task file deleted: $taskUrl');
    
    // Also delete associated ACR/ACL files if they exist
    try {
      await _deleteResource('$taskUrl.acr');
    } catch (e) {
      debugPrint('No ACR file to delete or delete failed: $e');
    }
    
    try {
      await _deleteResource('$taskUrl.acl');
    } catch (e) {
      debugPrint('No ACL file to delete or delete failed: $e');
    }
    
    try {
      await _deleteResource('$taskUrl.acr.meta');
    } catch (e) {
      debugPrint('No ACR.meta file to delete or delete failed: $e');
    }
  }

  // Auth / Session
  static Future<bool> logout(BuildContext context) async {
    try {
      debugPrint('Logging out user...');
      final success = await deleteLogIn();
      if (success) {
        debugPrint('User logged out successfully');
        if (context.mounted) {
          restartApp(context);
        }
        return true;
      } else {
        debugPrint('Failed to delete login information');
        return false;
      }
    } catch (e) {
      debugPrint('Error during logout: $e');
      return false;
    }
  }

  static Future<void> logoutWithPopup(BuildContext context) async {
    try {
      debugPrint('Showing logout popup...');
      await logoutPopup(context, const Text('Logout'));
      debugPrint('Logout popup completed');
    } catch (e) {
      debugPrint('Error during logout popup: $e');
      rethrow;
    }
  }

  static Future<bool> isLoggedIn() async {
    try {
      final webId = await getWebId();
      return webId != null && webId.isNotEmpty;
    } catch (e) {
      debugPrint('Error checking login status: $e');
      return false;
    }
  }

static Future<List<Task>> loadTasks(BuildContext context, StatefulWidget widget) async {
  debugPrint('=== STARTING LOAD TASKS ===');

  final loggedIn = await loginIfRequired(context);
  if (!loggedIn) throw Exception('Login required');
  
  await Future.delayed(Duration(milliseconds: 300));

  String webId = await getWebId() as String;
  webId = webId.replaceAll(profCard, '');
  final fullDirPath = '$webId$tasksDirRel';
  debugPrint('Tasks directory: $fullDirPath');

  // Ensure dir exists (no-op if present)
  try { await _ensureDirectoryExists(fullDirPath); } catch (_) {}

  // List container
  final files = await _listContainerTurtleFiles(fullDirPath);
  debugPrint('Found in container: $files');

  final tasks = <Task>[];

  for (final f in files.where((f) => f.startsWith(_taskPrefix) && f.endsWith(_taskExt))) {
    try {
      debugPrint('Reading task file: $f');
      // Read each task file
      final decrypted = await readPod('$f', context, widget);

      //peek to verify we see TTL, not encData
      debugPrint('Decrypted TTL head ($f): ${decrypted.substring(0, decrypted.length > 300 ? 300 : decrypted.length)}');

      if (decrypted.trim().isNotEmpty) {
        final parsed = _parseTasksFromTurtle(decrypted);
        tasks.addAll(parsed);
      }
    } catch (e) {
      debugPrint('Failed reading $f via readPod: $e');
    }
  }

  // Legacy file 
  if (files.contains(legacyTasksFile)) {
    try {
      final legacy = await readPod('$tasksDirRel$legacyTasksFile', context, widget);
      final parsed = _parseTasksFromTurtle(legacy);
      final ids = tasks.map((t) => t.id).toSet();
      for (final t in parsed) {
        if (!ids.contains(t.id)) tasks.add(t);
      }
    } catch (e) {
      debugPrint('Failed reading legacy $legacyTasksFile via readPod: $e');
    }
  }

  debugPrint('Loaded ${tasks.length} total tasks');
  return tasks;
}

// Turtle Decrypter helper
static Future<String?> _httpGetTextTurtle(String fullUrl) async {
  final (:accessToken, :dPopToken) = await getTokensForResource(fullUrl, 'GET');
  final res = await http.get(
    Uri.parse(fullUrl),
    headers: {
      'Accept': 'text/turtle',
      'Authorization': 'DPoP $accessToken',
      'DPoP': dPopToken,
    },
  );
  if (res.statusCode == 200) return res.body;
  debugPrint('GET $fullUrl failed: ${res.statusCode} ${res.body}');
  return null;
}


  /// Sync local tasks to the POD using one file per task.
  static Future<void> saveTasks(List<Task> tasks, BuildContext context, StatefulWidget widget) async {
    debugPrint('Starting per-task sync to POD... (#${tasks.length})');

    final loggedIn = await loginIfRequired(context);
    if (!loggedIn) throw Exception('Login required');

    String webId = await getWebId() as String;
    webId = webId.replaceAll(profCard, '');
    final fullDirPath = '$webId$tasksDirRel';
    debugPrint('Ensuring directory exists: $fullDirPath');

    await _ensureDirectoryExists(fullDirPath);

    // Compute expected filenames for current local tasks
    final expected = <String>{for (final t in tasks) _fileNameForTask(t.id)};

    // List current remote files
    final remoteFiles = await _listContainerTurtleFiles(fullDirPath);
    final remoteTaskFiles = remoteFiles
        .where((f) => f.startsWith(_taskPrefix) && f.endsWith(_taskExt))
        .toSet();

    for (final task in tasks) {
      final fileName = _fileNameForTask(task.id);
      final turtle = _taskToTurtle(task);

      debugPrint('Writing $fileName ...');

      final status = await writePod(
        fileName,
        turtle,
        context,
        widget,
        encrypted: false,
      );

      debugPrint('Write $fileName status: $status');

      if (status == SolidFunctionCallStatus.success) {
        final ownerWebId = await currentWebId();
        final fileUrl = '$fullDirPath$fileName';

        // Generate preset ACR string
        final collaboratorWebId = "https://pods.acp.solidcommunity.au/gooseacp/profile/card#me";

        await AcpPresets.writeAcrForResource(
          fileUrl,
          ownerWebId,
          allowReadWebIds: [collaboratorWebId],
          allowWriteWebIds: [collaboratorWebId],
        );

        try {
          await _deleteResource('$fileUrl.acl');
          debugPrint('Deleted auto-generated .acl file for $fileName');
        } catch (e) {
          debugPrint('No .acl file to delete: $e');
        }
        await PermissionLogService.logPermissionChange(
          resourceUrl: fileUrl,
          ownerWebId: ownerWebId,
          granterWebId: ownerWebId,
          recipientWebId: collaboratorWebId,
          permissionList: ['read', 'write'],
          permissionType: 'grant',
          acpPattern: 'basic',
        );
      }

    }
    debugPrint('Per-task sync complete.');
  }

  static String _fileNameForTask(String id) => '$_taskPrefix${id}$_taskExt';

  /// TTL with embedded single-task JSON inside `solid:content """ ... """`.
  static String _taskToTurtle(Task task) {
    final jsonObj = task.toJson(); // {id,title,isCompleted,dueDate,...}
    final taskJsonStr = json.encode(jsonObj);

    return '''@prefix : <#> .
@prefix solid: <http://www.w3.org/ns/solid/terms#> .
@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .

:task a solid:Resource ;
    solid:content """$taskJsonStr""" ;
    :lastUpdated "${DateTime.now().toIso8601String()}"^^xsd:dateTime .
''';
  }

  static List<Task> _parseTasksFromTurtle(String ttl) {
  try {
    final src = ttl.trim();

    // Raw JSON file
    if (src.startsWith('{') || src.startsWith('[')) {
      return _decodedJsonToTasks(json.decode(src));
    }

    // Any triple-double-quoted block(s): """ ... """
    final tripleDq = RegExp(r'"""(.*?)"""', dotAll: true);
    for (final m in tripleDq.allMatches(ttl)) {
      final payload = m.group(1)!;
      final decoded = _tryJsonDecode(payload);
      if (decoded != null) return _decodedJsonToTasks(decoded);
    }

    // Any triple-single-quoted block(s): ''' ... '''
    final tripleSq = RegExp(r"'''(.*?)'''", dotAll: true);
    for (final m in tripleSq.allMatches(ttl)) {
      final payload = m.group(1)!;
      final decoded = _tryJsonDecode(payload);
      if (decoded != null) return _decodedJsonToTasks(decoded);
    }

    // Typed literal: "...."^^rdf:JSON (or any ^^type / @lang)
    final typed = RegExp(r'"((?:[^"\\]|\\.)*)"\s*(\^\^|@)', dotAll: true);
    for (final m in typed.allMatches(ttl)) {
      final literalEscaped = m.group(1)!;
      final literal = _unescapeTurtleString(literalEscaped);
      final decoded = _tryJsonDecode(literal);
      if (decoded != null) return _decodedJsonToTasks(decoded);
    }

    // Fallback: widest JSON-looking span { ... } or [ ... ]
    int i = ttl.indexOf('{');
    int j = ttl.lastIndexOf('}');
    if (i != -1 && j > i) {
      final decoded = _tryJsonDecode(ttl.substring(i, j + 1));
      if (decoded != null) return _decodedJsonToTasks(decoded);
    }
    i = ttl.indexOf('[');
    j = ttl.lastIndexOf(']');
    if (i != -1 && j > i) {
      final decoded = _tryJsonDecode(ttl.substring(i, j + 1));
      if (decoded != null) return _decodedJsonToTasks(decoded);
    }

    debugPrint('Parser: no JSON payload detected in TTL.');
    return [];
  } catch (e) {
    debugPrint('Failed to parse turtle data: $e');
    return [];
  }
}

static dynamic _tryJsonDecode(String s) {
  try { return json.decode(s.trim()); } catch (_) { return null; }
}

static String _unescapeTurtleString(String s) {
  // Minimal unescape for JSON strings appearing inside Turtle quoted literals
  return s
      .replaceAll(r'\"', '"')
      .replaceAll(r'\\', '\\')
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\t', '\t')
      .replaceAll(r'\r', '\r');
}


  static List<Task> _decodedJsonToTasks(dynamic decoded) {
    final tasks = <Task>[];
    if (decoded is List) {
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          if (!item.containsKey(updateTimeLabel)) {
            tasks.add(Task.fromJson(item));
          }
        }
      }
    } else if (decoded is Map<String, dynamic>) {
      // Single task object
      tasks.add(Task.fromJson(decoded));
    }
    return tasks;
  }

  static Future<void> _ensureDirectoryExists(String dirPath) async {
    try {
      final dirExists = await _checkResourceStatus(dirPath, fileFlag: false);
      if (!dirExists) {
        debugPrint('Directory does not exist, attempting to create: $dirPath');
        await _createDirectory(dirPath);
      }
    } catch (e) {
      debugPrint('Error checking/creating directory: $e');
      rethrow;
    }
  }

  static Future<void> _createDirectory(String dirPath) async {
    try {
      final (:accessToken, :dPopToken) = await getTokensForResource(dirPath, 'PUT');
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
      if (response.statusCode != 201 && response.statusCode != 204) {
        debugPrint('Failed to create directory. Status: ${response.statusCode}, Body: ${response.body}');
        throw Exception('Failed to create directory: ${response.statusCode}');
      }
      debugPrint('Directory created successfully');
    } catch (e) {
      debugPrint('Error creating directory: $e');
      rethrow;
    }
  }

  static Future<bool> _checkResourceStatus(String resUrl, {bool fileFlag = true}) async {
    try {
      debugPrint('Checking resource status: $resUrl');
      final (:accessToken, :dPopToken) = await getTokensForResource(resUrl, 'GET');
      final response = await http.get(
        Uri.parse(resUrl),
        headers: <String, String>{
          // Use Accept for GETs
          'Accept': fileFlag ? 'text/turtle' : 'text/turtle',
          'Authorization': 'DPoP $accessToken',
          'Link': fileFlag
              ? '<http://www.w3.org/ns/ldp#Resource>; rel="type"'
              : '<http://www.w3.org/ns/ldp#BasicContainer>; rel="type"',
          'DPoP': dPopToken,
        },
      );
      debugPrint('Resource check response: ${response.statusCode}');
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) {
      debugPrint('Failed to check resource status: $e');
      return false;
    }
  }
  static Future<List<String>> _listContainerTurtleFiles(String fullDirPath) async {
    try {
      final (:accessToken, :dPopToken) = await getTokensForResource(fullDirPath, 'GET');
      final response = await http.get(
        Uri.parse(fullDirPath),
        headers: <String, String>{
          'Accept': 'text/turtle',
          'Authorization': 'DPoP $accessToken',
          'Link': '<http://www.w3.org/ns/ldp#BasicContainer>; rel="type"',
          'DPoP': dPopToken,
        },
      );

      if (response.statusCode != 200) {
        debugPrint('List container failed: ${response.statusCode} ${response.body}');
        return [];
      }

      final body = response.body;
      // Very simple parse: collect <...something.ttl>
      final reg = RegExp(r'<([^>]+\.ttl)>');
      final matches = reg.allMatches(body);
      final files = <String>[];
      for (final m in matches) {
        final url = m.group(1)!;
        final seg = Uri.parse(url).pathSegments.last;
        files.add(seg);
      }
      return files.toSet().toList(); // unique
    } catch (e) {
      debugPrint('Error listing container: $e');
      return [];
    }
  }

  static Future<void> _deleteResource(String fullResUrl) async {
    final (:accessToken, :dPopToken) = await getTokensForResource(fullResUrl, 'DELETE');
    final res = await http.delete(
      Uri.parse(fullResUrl),
      headers: <String, String>{
        'Authorization': 'DPoP $accessToken',
        'DPoP': dPopToken,
      },
    );
    // Error Handling: POD may return 204 for successful delete
    if (res.statusCode != 200 && res.statusCode != 204 && res.statusCode != 205) {
      debugPrint('Delete failed for $fullResUrl => ${res.statusCode} ${res.body}');
      throw Exception('Delete failed: ${res.statusCode}');
    }
  }
  // ACP IMPLEMENTATION EXPERIMENTAL
  static Future<String?> fetchAcrForTask(String taskFileUrl) async {
    try {
      final acrUrl = '$taskFileUrl.acr';
      final (:accessToken, :dPopToken) = await getTokensForResource(acrUrl, 'GET');
      final res = await http.get(
        Uri.parse(acrUrl),
        headers: {
          'Accept': 'text/turtle',
          'Authorization': 'DPoP $accessToken',
          'DPoP': dPopToken,
        },
      );
      return res.statusCode == 200 ? res.body : null;
    } catch (e) {
      debugPrint('Error fetching ACR: $e');
      return null;
    }
  }

  static Future<String?> fetchAcr(String resourceUrl) async {
    try {
      final acrUrl = '$resourceUrl.acr';
      final (:accessToken, :dPopToken) = await getTokensForResource(acrUrl, 'GET');
      final res = await http.get(
        Uri.parse(acrUrl),
        headers: {
          'Accept': 'text/turtle',
          'Authorization': 'DPoP $accessToken',
          'DPoP': dPopToken,
        },
      );
      return res.statusCode == 200 ? res.body : null;
    } catch (e) {
      debugPrint('Error fetching ACR for $resourceUrl: $e');
      return null;
    }
  }

  static Future<String> currentWebId() async {
    final raw = await getWebId();
    if (raw == null || raw.isEmpty) {
      throw Exception("User is not logged in or WebID unavailable.");
    }
    return raw.replaceAll(profCard, '');
  }

  static Future<String> taskFileUrl(String taskId) async {
    final webId = await currentWebId();
    return '$webId$tasksDirRel${_taskPrefix}${taskId}${_taskExt}';
  }


  /// Write an ACR (Access Control Resource) for any Task resource.
  static Future<void> writeAcrForResource(
    String resourceUrl,
    String ownerWebId, {
    List<String>? allowReadWebIds,
    List<String>? allowWriteWebIds,
  }) async {
    try {
      final acrUrl = '$resourceUrl.acr';
      final acrBody = _generateAcr(
        ownerWebId,
        allowReadWebIds: allowReadWebIds,
        allowWriteWebIds: allowWriteWebIds,
      );

      final (:accessToken, :dPopToken) = await getTokensForResource(acrUrl, 'PUT');
      final res = await http.put(
        Uri.parse(acrUrl),
        headers: {
          'Content-Type': 'text/turtle',
          'Authorization': 'DPoP $accessToken',
          'DPoP': dPopToken,
        },
        body: acrBody,
      );

      if ([200, 201, 204, 205].contains(res.statusCode)) {
        debugPrint('ACR created/updated for $resourceUrl');
      } else {
        debugPrint('Failed to write ACR for $resourceUrl => ${res.statusCode} ${res.body}');
        throw Exception('Failed to write ACR: ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('Error writing ACR for $resourceUrl: $e');
      rethrow;
    }
  }

  /// Generate an ACR body with owner + optional shared access.
  static String _generateAcr(
    String ownerWebId, {
    List<String>? allowReadWebIds,
    List<String>? allowWriteWebIds,
    List<String>? allowControlWebIds,
    bool publicRead = false,
  }) {
    final readList = allowReadWebIds ?? [];
    final writeList = allowWriteWebIds ?? [];
    final controlList = allowControlWebIds ?? [];

    final readMatchers = readList.map((id) => '<$id>').join(' ');
    final writeMatchers = writeList.map((id) => '<$id>').join(' ');
    final controlMatchers = controlList.map((id) => '<$id>').join(' ');

    // add public agent if publicRead is true
    final publicAgent = publicRead ? '<http://www.w3.org/ns/solid/acp#PublicAgent>' : '';

    return '''
  @prefix acp: <http://www.w3.org/ns/solid/acp#>.
  @prefix acl: <http://www.w3.org/ns/auth/acl#>.

  <> a acp:AccessControlResource;
    acp:accessControl <#ownerAccess>, <#sharedAccess>.

  <#ownerAccess> a acp:AccessControl;
    acp:apply <#ownerPolicy>.

  <#ownerPolicy> a acp:Policy;
    acp:allow acl:Read, acl:Write, acl:Control;
    acp:anyOf ( <$ownerWebId/profile/card#me> ).

  <#sharedAccess> a acp:AccessControl;
    acp:apply <#sharedPolicy>.

  <#sharedPolicy> a acp:Policy;
    ${readList.isNotEmpty || publicRead ? 'acp:allow acl:Read;' : ''}
    ${writeList.isNotEmpty ? 'acp:allow acl:Write;' : ''}
    ${controlList.isNotEmpty ? 'acp:allow acl:Control;' : ''}
    acp:anyOf ( $readMatchers $writeMatchers $controlMatchers $publicAgent ).
  ''';
  }

}
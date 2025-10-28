import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:solidpod/solidpod.dart';
import '../models/task.dart';
import '../main.dart'; 
import 'pod_service_acp.dart';
import 'permission_log_service.dart';
import '../utils/pod_utils.dart';

class PodService {
  // Constants now come from PodUtils
  static const String updateTimeLabel = 'lastUpdated';

  static Future<void> openShareUiForTask(
    BuildContext context,
    StatefulWidget returnTo,
    String taskId,
  ) async {
    final fileName = PodUtils.taskFileName(taskId); 
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
    // Delete main task file
    await PodUtils.deleteResource(taskUrl);
    
    debugPrint('Task file deleted: $taskUrl');
    
    // Also delete associated ACR/ACL files if they exist
    try {
      await PodUtils.deleteResource('$taskUrl.acr');
    } catch (e) {
      debugPrint('No ACR file to delete or delete failed: $e');
    }
    
    try {
      await PodUtils.deleteResource('$taskUrl.acl');
    } catch (e) {
      debugPrint('No ACL file to delete or delete failed: $e');
    }
    
    try {
      await PodUtils.deleteResource('$taskUrl.acr.meta');
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

    String webId = await PodUtils.getCurrentWebIdClean();
    final fullDirPath = '$webId${PodUtils.tasksDirRel}';
    debugPrint('Tasks directory: $fullDirPath');

    // Ensure dir exists (no-op if present)
    try { 
      await PodUtils.ensureDirectoryExists(fullDirPath); 
    } catch (_) {}

    // List container
    final files = await PodUtils.listTurtleFiles(fullDirPath);
    debugPrint('Found in container: $files');

    final tasks = <Task>[];

    for (final f in files.where((f) => PodUtils.isTaskFile(f))) {
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
    if (files.contains(PodUtils.legacyTasksFile)) {
      try {
        final legacy = await readPod('${PodUtils.tasksDirRel}${PodUtils.legacyTasksFile}', context, widget);
        final parsed = _parseTasksFromTurtle(legacy);
        final ids = tasks.map((t) => t.id).toSet();
        for (final t in parsed) {
          if (!ids.contains(t.id)) tasks.add(t);
        }
      } catch (e) {
        debugPrint('Failed reading legacy ${PodUtils.legacyTasksFile} via readPod: $e');
      }
    }

    debugPrint('Loaded ${tasks.length} total tasks');
    return tasks;
  }

  /// Sync local tasks to the POD using one file per task.
  static Future<void> saveTasks(List<Task> tasks, BuildContext context, StatefulWidget widget) async {
    debugPrint('Starting per-task sync to POD... (#${tasks.length})');

    final loggedIn = await loginIfRequired(context);
    if (!loggedIn) throw Exception('Login required');

    String webId = await PodUtils.getCurrentWebIdClean();
    final fullDirPath = '$webId${PodUtils.tasksDirRel}';
    debugPrint('Ensuring directory exists: $fullDirPath');

    await PodUtils.ensureDirectoryExists(fullDirPath);

    // Compute expected filenames for current local tasks
    final expected = <String>{for (final t in tasks) PodUtils.taskFileName(t.id)};

    // List current remote files
    final remoteFiles = await PodUtils.listTurtleFiles(fullDirPath);
    final remoteTaskFiles = remoteFiles
        .where((f) => PodUtils.isTaskFile(f))
        .toSet();

    for (final task in tasks) {
      final fileName = PodUtils.taskFileName(task.id);
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
        final ownerWebId = await PodUtils.getCurrentWebIdFull();
        final fileUrl = '$fullDirPath$fileName';

        // Set ACR with only owner permissions (no collaborators)
        await AcpPresets.writeAcrForResource(
          fileUrl,
          ownerWebId,
        );

        debugPrint('ACR created for $fileName with owner-only access');
      }
    }

    // Delete orphaned task files (tasks that exist remotely but not locally)
    final orphans = remoteTaskFiles.difference(expected);
    for (final orphan in orphans) {
      try {
        final orphanUrl = '$fullDirPath$orphan';
        debugPrint('Deleting orphaned task file: $orphan');
        await deleteTaskFile(orphanUrl);
      } catch (e) {
        debugPrint('Failed to delete orphaned file $orphan: $e');
      }
    }

    debugPrint('=== SAVE COMPLETE ===');
  }

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

  // ACR Operations
  static Future<String?> fetchAcrForTask(String taskFileUrl) async {
    return fetchAcr(taskFileUrl);
  }

  static Future<String?> fetchAcr(String resourceUrl) async {
    try {
      final acrUrl = '$resourceUrl.acr';
      final content = await PodUtils.readTurtleContent(acrUrl);
      return content;
    } catch (e) {
      debugPrint('Error fetching ACR for $resourceUrl: $e');
      return null;
    }
  }

  /// Get task file URL for a task ID
  /// Wrapper for PodUtils.taskFileUrl() for backward compatibility
  static Future<String> taskFileUrl(String taskId) async {
    return PodUtils.taskFileUrl(taskId);
  }

  /// Write an ACR (Access Control Resource) for any Task resource.
  /// 
  /// DEPRECATED: Use AcpPresets.writeAcrForResource instead
  @Deprecated('Use AcpPresets.writeAcrForResource instead')
  static Future<void> writeAcrForResource(
    String resourceUrl,
    String ownerWebId, {
    List<String>? allowReadWebIds,
    List<String>? allowWriteWebIds,
  }) async {
    await AcpPresets.writeAcrForResource(
      resourceUrl,
      ownerWebId,
      allowReadWebIds: allowReadWebIds,
      allowWriteWebIds: allowWriteWebIds,
    );
  }
}
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:solidpod/solidpod.dart';
import '../models/task.dart';

class PodService {
  static const String profCard = '/profile/card#me';
  static const String myTasksFile = 'tasks.ttl';
  static const String updateTimeLabel = 'lastUpdated';

  // Load tasks from POD
  static Future<List<Task>> loadTasks(BuildContext context, StatefulWidget widget) async {
    debugPrint('Starting to load tasks from POD...');
    
    final loggedIn = await loginIfRequired(context);
    if (!loggedIn) {
      throw Exception('Login required');
    }

    String webId = await getWebId() as String;
    debugPrint('WebID: $webId');
    
    webId = webId.replaceAll(profCard, '');
    debugPrint('Base WebID: $webId');

    // Use relative path for solidpod package
    final relativePath = '/solidtasks/data/$myTasksFile';
    final fullTaskFileUrl = '${webId}$relativePath';
    debugPrint('Task file URL: $fullTaskFileUrl');

    bool resExist = await _checkResourceStatus(fullTaskFileUrl);
    debugPrint('Resource exists: $resExist');
    
    if (!resExist) {
      debugPrint('Task file does not exist, returning empty list');
      return [];
    }

    String taskDataStr = await readPod(
      myTasksFile,  // Use relative path only
      context,
      widget,
    );

    debugPrint('Raw data from POD: ${taskDataStr.substring(0, taskDataStr.length > 200 ? 200 : taskDataStr.length)}...');

    if (taskDataStr.isEmpty) {
      return [];
    }

    try {
      // Try to parse as JSON first (for backwards compatibility)
      if (taskDataStr.trim().startsWith('[') || taskDataStr.trim().startsWith('{')) {
        final decodedData = json.decode(taskDataStr);
        List<Task> tasks = [];
        
        if (decodedData is List) {
          for (var taskJson in decodedData) {
            if (taskJson is Map<String, dynamic> && !taskJson.containsKey(updateTimeLabel)) {
              tasks.add(Task.fromJson(taskJson));
            }
          }
        }
        debugPrint('Loaded ${tasks.length} tasks from JSON format');
        return tasks;
      } else {
        // Parse as JSON embedded in Turtle format
        return _parseTasksFromTurtle(taskDataStr);
      }
    } catch (e) {
      debugPrint('Failed to parse task data: $e');
      throw Exception('Failed to parse task data: $e');
    }
  }

  // Save tasks to POD
  static Future<void> saveTasks(List<Task> tasks, BuildContext context, StatefulWidget widget) async {
    debugPrint('Starting to save tasks to POD...');
    
    final loggedIn = await loginIfRequired(context);
    if (!loggedIn) {
      throw Exception('Login required');
    }

    String webId = await getWebId() as String;
    debugPrint('WebID for saving: $webId');
    
    webId = webId.replaceAll(profCard, '');
    
    // Use relative path for directory operations
    final relativeDirPath = '/solidtasks/data/';
    final fullDirPath = '${webId}$relativeDirPath';
    debugPrint('Ensuring directory exists: $fullDirPath');
    
    try {
      await _ensureDirectoryExists(fullDirPath);
    } catch (e) {
      debugPrint('Failed to ensure directory exists: $e');
      // Continue anyway, might still work
    }

    // Create the JSON structure with timestamp
    List<Map<String, dynamic>> taskList = [
      {updateTimeLabel: DateTime.now().toIso8601String()}
    ];
    
    for (Task task in tasks) {
      taskList.add(task.toJson());
    }

    String taskJsonStr = json.encode(taskList);
    debugPrint('JSON to save: $taskJsonStr');

    // Simplified Turtle format
    String turtleContent = '''@prefix : <#> .
@prefix solid: <http://www.w3.org/ns/solid/terms#> .
@prefix foaf: <http://xmlns.com/foaf/0.1/> .

:tasks a solid:Resource ;
    solid:content """$taskJsonStr""" .
''';

    debugPrint('Turtle content to save: ${turtleContent.substring(0, turtleContent.length > 300 ? 300 : turtleContent.length)}...');

    // Use RELATIVE path for writePod
    final relativePath = '/solidtasks/data/$myTasksFile';
    debugPrint('Writing to relative path: $relativePath');

    final writeDataStatus = await writePod(
      myTasksFile,  // Use relative path only
      turtleContent,
      context,
      widget,
    );

    debugPrint('Write status: $writeDataStatus');

    if (writeDataStatus != SolidFunctionCallStatus.success) {
      throw Exception('Failed to save tasks to POD. Status: $writeDataStatus');
    }
    
    debugPrint('Successfully saved tasks to POD');
  }

  // Private helper methods
  static List<Task> _parseTasksFromTurtle(String turtleData) {
    try {
      debugPrint('Parsing turtle data...');
      // Look for data embedded in turtle
      final jsonStartIndex = turtleData.indexOf('[');
      final jsonEndIndex = turtleData.lastIndexOf(']');
      
      if (jsonStartIndex != -1 && jsonEndIndex != -1 && jsonEndIndex > jsonStartIndex) {
        final jsonStr = turtleData.substring(jsonStartIndex, jsonEndIndex + 1);
        debugPrint('Extracted JSON: $jsonStr');
        
        final decodedData = json.decode(jsonStr);
        List<Task> tasks = [];
        
        if (decodedData is List) {
          for (var taskJson in decodedData) {
            if (taskJson is Map<String, dynamic> && !taskJson.containsKey(updateTimeLabel)) {
              tasks.add(Task.fromJson(taskJson));
            }
          }
        }
        debugPrint('Loaded ${tasks.length} tasks from Turtle format');
        return tasks;
      }
      debugPrint('No JSON found in turtle data');
      return [];
    } catch (e) {
      debugPrint('Failed to parse turtle data: $e');
      return [];
    }
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
          'Content-Type': fileFlag ? 'text/turtle' : 'application/octet-stream',
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
}
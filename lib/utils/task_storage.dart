// lib/utils/task_storage.dart

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solidpod/solidpod.dart';

import '../models/task.dart';

class TaskStorage {
  /// Load tasks from your Pod if available, else from local cache.
  static Future<List<Task>> loadTasks(
    BuildContext context,
    Widget childPage,
  ) async {
    // 1) Make sure the user is logged in
    await loginIfRequired(context);

    // 2) Compute the directory + file URL (for reference/debug)
    final dirUrl = await getDirUrl(await getDataDirPath());
    final fileUrl = '$dirUrl/tasks.json';

    String rawJson = '[]';

    try {
      // 3) Try reading tasks.json from the Pod
      rawJson = await readPod('tasks.json', context, childPage);
      // 4) Update local cache so we have it offline
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('tasks.json', rawJson);
    } catch (_) {
      // If the file doesn't exist (404) or network fails,
      // fall back to whatever’s in SharedPreferences.
      final prefs = await SharedPreferences.getInstance();
      rawJson = prefs.getString('tasks.json') ?? '[]';
    }

    // 5) Deserialize into your Task model
    final List list = json.decode(rawJson);
    return list.map((e) => Task.fromJson(e)).toList();
  }

  /// Save tasks both locally and to your Solid Pod.
  static Future<bool> saveTasks(
    BuildContext context,
    Widget childPage,
    List<Task> tasks,
  ) async {
    // 1) Bump each task’s updatedAt for sync logic
    final now = DateTime.now();
    for (var t in tasks) {
      t.updatedAt = now;
    }

    // 2) Serialize
    final rawJson = json.encode(tasks.map((t) => t.toJson()).toList());

    // 3) Write local cache
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tasks.json', rawJson);

    // 4) Push to your Pod
    await loginIfRequired(context);
    try {
      final status = await writePod(
        'tasks.json',    // relative path under your appDirectory
        rawJson,
        context,
        childPage,
      );
      return status == SolidFunctionCallStatus.success;
    } catch (_) {
      // If writePod throws or fails, return false
      return false;
    }
  }
}

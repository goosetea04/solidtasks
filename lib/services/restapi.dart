import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:http/http.dart' as http;
import 'package:solidpod/solidpod.dart';

Future<LoadedTasks> loadServerTaskData(
  BuildContext context,
  Widget childPage,
) async {
  final loggedIn = await loginIfRequired(context);
  String webId = await getWebId() as String;
  webId = webId.replaceAll(profCard, '');

  String taskJsonStr = '';

  if (loggedIn) {
    final dataDirPath = await getDataDirPath();
    final dataDirUrl = await getDirUrl(dataDirPath);
    final taskFileUrl = dataDirUrl + myTasksFile;

    final acrUrl = taskFileUrl + '.acr';
    final acrBody = _defaultAcrForAllTasks(webId);

    bool resExist = await checkResourceStatus(taskFileUrl);

    if (resExist) {
      taskJsonStr = await readPod(
        taskFileUrl.replaceAll(webId, ''),
        context,
        childPage,
      );
    }
  }

  String updatedTimeStr = '';
  var categories = <String, Category>{};

  if (taskJsonStr.isEmpty) return LoadedTasks({}, {});

  final decodedCategories = json.decode(taskJsonStr);

  for (var json in decodedCategories) {
    if (json.containsKey(updateTimeLabel)) {
      updatedTimeStr = json[updateTimeLabel];
      continue;
    }
    var category = Category.fromJson(json);
    String id = json['id'];
    categories[id] = category;
  }

  // Return a LoadedTasks object
  return LoadedTasks({updateTimeLabel: updatedTimeStr}, categories);
}

Future<bool> saveServerTaskData(
  String taskJsonStr,
  BuildContext context,
  Widget childPage,
) async {
  final loggedIn = await loginIfRequired(context);
  String webId = await getWebId() as String;
  webId = webId.replaceAll(profCard, '');

  // Map taskMap = {};

  if (loggedIn) {

    final writeDataStatus = await writePod(
      myTasksFile,
      taskJsonStr,
      context,
      childPage,
      // encrypted: false, // save in plain text for now
    );

    if (writeDataStatus != SolidFunctionCallStatus.success) {
      // throw Exception('Error occured. Please try again!');
      return false;
    } else {
      return true;
    }
  } else {
    return false;
  }
}

// Check if a resource exists in the Pod
Future<bool> checkResourceStatus(String resUrl, {bool fileFlag = true}) async {
  final (:accessToken, :dPopToken) = await getTokensForResource(resUrl, 'GET');
  final response = await http.get(
    Uri.parse(resUrl),
    headers: <String, String>{
      'Content-Type': fileFlag ? '*/*' : 'application/octet-stream',
      'Authorization': 'DPoP $accessToken',
      'Link': fileFlag
          ? '<http://www.w3.org/ns/ldp#Resource>; rel="type"'
          : '<http://www.w3.org/ns/ldp#BasicContainer>; rel="type"',
      'DPoP': dPopToken,
    },
  );

  if (response.statusCode == 200 || response.statusCode == 204) {
    return true;
  } else if (response.statusCode == 404) {
    return false;
  } else {
    debugPrint(
      'Failed to check resource status.\n'
      'URL: $resUrl\n'
      'ERR: ${response.body}',
    );
    return false;
  }
}
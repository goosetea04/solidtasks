import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:solidpod/solidpod.dart';
import 'pod_utils.dart';

Future<LoadedTasks> loadServerTaskData(
  BuildContext context,
  Widget childPage,
) async {
  final loggedIn = await loginIfRequired(context);
  String webId = await PodUtils.getCurrentWebIdClean();

  String taskJsonStr = '';

  if (loggedIn) {
    final dataDirPath = await getDataDirPath();
    final dataDirUrl = await getDirUrl(dataDirPath);
    final taskFileUrl = dataDirUrl + myTasksFile;

    final acrUrl = taskFileUrl + '.acr';
    final acrBody = _defaultAcrForAllTasks(webId);

    bool resExist = await PodUtils.checkResourceExists(taskFileUrl);

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
  String webId = await PodUtils.getCurrentWebIdClean();

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

// Helper function for default ACR (kept for backward compatibility)
String _defaultAcrForAllTasks(String webId) {
  // This is a simplified ACR - you may want to use AcpPresets instead
  return '''@prefix acp: <http://www.w3.org/ns/solid/acp#> .
@prefix acl: <http://www.w3.org/ns/auth/acl#> .

<> a acp:AccessControlResource ;
   acp:accessControl <#ownerAccess> .

<#ownerAccess> a acp:AccessControl ;
   acp:apply <#ownerPolicy> .

<#ownerPolicy> a acp:Policy ;
   acp:allow acl:Read, acl:Write, acl:Control ;
   acp:anyOf ( <$webId${PodUtils.profCard}> ) .
''';
}
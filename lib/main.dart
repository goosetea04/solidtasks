import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solidpod/solidpod.dart';
import 'models/task.dart';
import 'utils/task_storage.dart';
import 'pages/homepage.dart';

void main() {
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My To‑Do App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      debugShowCheckedModeBanner: false,
      home: buildSolidLogin(),
    );
  }
}

// Build the Solid login widget
Widget buildSolidLogin() {
  return Builder(
    builder: (context) {
      return SolidLogin(
        required: false,
        title: 'My To‑Do App',
        appDirectory: 'mytasks',
        webID: 'https://pod.solidcommunity.au/profile/card#me', 
        child: const TodoHomePage(),
      );
    },
  );
}
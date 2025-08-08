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
      title: 'SolidTasks',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      debugShowCheckedModeBanner: false,
      home: const SolidTasksApp(),
    );
  }
}

// Wrapper class to handle the SolidLogin
class SolidTasksApp extends StatelessWidget {
  const SolidTasksApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SolidLogin(
      required: true,
      title: 'SolidTasks',
      logo: const AssetImage('assets/logo.png'),
      child: const TodoHomePage(),
    );
  }
}

// Helper function to restart the app (useful for logout)
void restartApp(BuildContext context) {
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(
      builder: (context) => const MyApp(),
    ),
    (route) => false,
  );
}
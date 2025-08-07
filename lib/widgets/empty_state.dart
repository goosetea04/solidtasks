import 'package:flutter/material.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.task_alt, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            'No tasks yet!',
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
          Text(
            'Add your first task above',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
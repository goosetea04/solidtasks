import 'package:flutter/material.dart';

class AddTaskWidget extends StatefulWidget {
  final Function(String) onAddTask;

  const AddTaskWidget({
    Key? key,
    required this.onAddTask,
  }) : super(key: key);

  @override
  State<AddTaskWidget> createState() => _AddTaskWidgetState();
}

class _AddTaskWidgetState extends State<AddTaskWidget> {
  final TextEditingController _taskController = TextEditingController();

  @override
  void dispose() {
    _taskController.dispose();
    super.dispose();
  }

  void _addTask() {
    if (_taskController.text.trim().isNotEmpty) {
      widget.onAddTask(_taskController.text.trim());
      _taskController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _taskController,
              decoration: const InputDecoration(
                hintText: 'Add a new task...',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onSubmitted: (_) => _addTask(),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _addTask,
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}
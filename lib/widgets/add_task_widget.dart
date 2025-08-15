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
  final _formKey = GlobalKey<FormState>();

  Future<void> _openAddTaskDialog() async {
    final titleController = TextEditingController();

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('New Task'),
        content: Form(
          key: _formKey,
          child: TextFormField(
            controller: titleController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Title *',
              hintText: 'e.g., Finish report draft',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submit(ctx, titleController),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Please enter a task title' : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => _submit(ctx, titleController),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _submit(BuildContext dialogContext, TextEditingController c) {
    if (_formKey.currentState?.validate() ?? false) {
      widget.onAddTask(c.text.trim());
      Navigator.of(dialogContext).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      heroTag: 'add_task_fab',
      icon: const Icon(Icons.add),
      label: const Text('Add task'),
      onPressed: _openAddTaskDialog,
    );
  }
}

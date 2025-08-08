import 'package:flutter/material.dart';
import '../models/task.dart';

class EditTaskDialog extends StatefulWidget {
  final Task task;
  final Function(String title, DateTime? dueDate) onSave;

  const EditTaskDialog({
    Key? key,
    required this.task,
    required this.onSave,
  }) : super(key: key);

  @override
  State<EditTaskDialog> createState() => _EditTaskDialogState();
}

class _EditTaskDialogState extends State<EditTaskDialog> {
  late TextEditingController _editController;
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    _editController = TextEditingController(text: widget.task.title);
    _selectedDate = widget.task.dueDate;
  }

  @override
  void dispose() {
    _editController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Task'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _editController,
            decoration: const InputDecoration(
              labelText: 'Task title',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  _selectedDate != null
                      ? 'Due: ${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}'
                      : 'No due date',
                ),
              ),
              TextButton(
                onPressed: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate ?? DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (date != null) {
                    setState(() {
                      _selectedDate = date;
                    });
                  }
                },
                child: const Text('Set Date'),
              ),
              if (_selectedDate != null)
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selectedDate = null;
                    });
                  },
                  child: const Text('Clear'),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_editController.text.trim().isNotEmpty) {
              widget.onSave(_editController.text.trim(), _selectedDate);
              Navigator.of(context).pop();
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// Helper function to show the dialog
Future<void> showEditTaskDialog(
  BuildContext context,
  Task task,
  Function(String title, DateTime? dueDate) onSave,
) {
  return showDialog<void>(
    context: context,
    builder: (context) => EditTaskDialog(
      task: task,
      onSave: onSave,
    ),
  );
}
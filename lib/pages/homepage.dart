import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/tasks_provider.dart';
import '../services/pod_service.dart';
import '../widgets/task_item.dart';
import '../widgets/add_task_widget.dart';
import '../widgets/edit_task_dialog.dart';
import '../widgets/empty_state.dart';

class TodoHomePage extends ConsumerStatefulWidget {
  const TodoHomePage({Key? key}) : super(key: key);

  @override
  ConsumerState<TodoHomePage> createState() => _TodoHomePageState();
}

class _TodoHomePageState extends ConsumerState<TodoHomePage> {
  bool _isLoading = false;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadTasksFromPod();
  }

  // Load tasks from POD
  Future<void> _loadTasksFromPod() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final tasks = await PodService.loadTasks(context, widget);
      ref.read(tasksProvider.notifier).setTasks(tasks);
    } catch (e) {
      debugPrint('Error loading tasks: $e');
      if (mounted) {
        _showErrorSnackBar('Failed to load tasks: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Save tasks to POD with better error handling
  Future<void> _saveTasksToPod() async {
    setState(() {
      _isSyncing = true;
    });

    try {
      final tasks = ref.read(tasksProvider);
      debugPrint('Saving ${tasks.length} tasks to POD...');
      await PodService.saveTasks(tasks, context, widget);
      
      if (mounted) {
        _showSuccessSnackBar('Tasks synced successfully!');
      }
    } catch (e) {
      debugPrint('Error saving tasks: $e');
      if (mounted) {
        _showErrorSnackBar('Failed to sync tasks: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
    }
  }

  // Task management methods
  void _addTask(String title) {
    ref.read(tasksProvider.notifier).addTask(title);
    _saveTasksToPod();
  }

  void _toggleTask(String id) {
    ref.read(tasksProvider.notifier).toggleTask(id);
    _saveTasksToPod();
  }

  void _deleteTask(String id) {
    ref.read(tasksProvider.notifier).deleteTask(id);
    _saveTasksToPod();
  }

  void _updateTask(String id, String newTitle, DateTime? dueDate) {
    ref.read(tasksProvider.notifier).updateTask(id, newTitle, dueDate: dueDate);
    _saveTasksToPod();
  }

  void _showEditTaskDialog(task) {
    showEditTaskDialog(
      context,
      task,
      (title, dueDate) => _updateTask(task.id, title, dueDate),
    );
  }

  // UI Helper methods
  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return const SizedBox(
      width: 20,
      height: 20,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tasksNotifier = ref.watch(tasksProvider.notifier);
    final tasks = ref.watch(tasksProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My To‑Do List'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          // Sync button
          IconButton(
            onPressed: _isSyncing ? null : _saveTasksToPod,
            icon: _isSyncing ? _buildLoadingIndicator() : const Icon(Icons.sync),
            tooltip: 'Sync with POD',
          ),
          // Refresh button
          IconButton(
            onPressed: _isLoading ? null : _loadTasksFromPod,
            icon: _isLoading ? _buildLoadingIndicator() : const Icon(Icons.refresh),
            tooltip: 'Reload from POD',
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Center(
              child: Text(
                '${tasksNotifier.completedCount}/${tasksNotifier.totalCount}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Add task section
          AddTaskWidget(onAddTask: _addTask),
          
          // Tasks list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : tasks.isEmpty
                    ? const EmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.all(8.0),
                        itemCount: tasks.length,
                        itemBuilder: (context, index) {
                          final task = tasks[index];
                          return TaskItem(
                            task: task,
                            onToggle: () => _toggleTask(task.id),
                            onDelete: () => _deleteTask(task.id),
                            onEdit: () => _showEditTaskDialog(task),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
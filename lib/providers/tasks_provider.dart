import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/task.dart';

// Provider for managing tasks state
final tasksProvider = StateNotifierProvider<TasksNotifier, List<Task>>((ref) {
  return TasksNotifier();
});

class TasksNotifier extends StateNotifier<List<Task>> {
  TasksNotifier() : super([]);

  void setTasks(List<Task> tasks) {
    state = tasks;
  }

  void addTask(
    String title, {
    String? description,
    DateTime? dueDate,
  }) {
    final task = Task(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      description: description,
      dueDate: dueDate,
    );
    state = [...state, task];
  }

  void toggleTask(String id) {
    state = state.map((task) {
      if (task.id == id) {
        return task.copyWith(isDone: !task.isDone);
      }
      return task;
    }).toList();
  }

  void deleteTask(String id) {
    state = state.where((task) => task.id != id).toList();
  }

  void updateTask(String id, String newTitle, {DateTime? dueDate}) {
    state = state.map((task) {
      if (task.id == id) {
        return task.copyWith(title: newTitle, dueDate: dueDate);
      }
      return task;
    }).toList();
  }

  // Computed values
  int get completedCount => state.where((task) => task.isDone).length;
  int get totalCount => state.length;
  List<Task> get pendingTasks => state.where((task) => !task.isDone).toList();
  List<Task> get completedTasks => state.where((task) => task.isDone).toList();
}
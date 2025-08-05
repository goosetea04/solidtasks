import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:solidpod/solidpod.dart';
import '../models/task.dart';

const String profCard = '/profile/card#me';
const String myTasksFile = 'tasks.ttl';
const String updateTimeLabel = 'lastUpdated';

// Riverpod provider for managing tasks
final tasksProvider = StateNotifierProvider<TasksNotifier, List<Task>>((ref) {
  return TasksNotifier();
});

class TasksNotifier extends StateNotifier<List<Task>> {
  TasksNotifier() : super([]);

  void setTasks(List<Task> tasks) {
    state = tasks;
  }

  void addTask(String title, {DateTime? dueDate}) {
    final task = Task(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      dueDate: dueDate,
    );
    state = [...state, task];
  }

  void toggleTask(String id) {
    state = state.map((task) {
      if (task.id == id) {
        task.isDone = !task.isDone;
        task.updatedAt = DateTime.now();
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
        task.title = newTitle;
        task.dueDate = dueDate;
        task.updatedAt = DateTime.now();
      }
      return task;
    }).toList();
  }
}

class TodoHomePage extends ConsumerStatefulWidget {
  const TodoHomePage({Key? key}) : super(key: key);

  @override
  ConsumerState<TodoHomePage> createState() => _TodoHomePageState();
}

class _TodoHomePageState extends ConsumerState<TodoHomePage> {
  final TextEditingController _taskController = TextEditingController();
  bool _isLoading = false;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadTasksFromPod();
  }

  @override
  void dispose() {
    _taskController.dispose();
    super.dispose();
  }

  // Load tasks from POD
  Future<void> _loadTasksFromPod() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final tasks = await _loadServerTaskData();
      ref.read(tasksProvider.notifier).setTasks(tasks);
    } catch (e) {
      debugPrint('Error loading tasks: $e'); // Added debug print
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load tasks: $e'),
            backgroundColor: Colors.red,
          ),
        );
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
      debugPrint('Saving ${tasks.length} tasks to POD...'); // Debug info
      await _saveServerTaskData(tasks);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tasks synced successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error saving tasks: $e'); // Added debug print
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to sync tasks: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
    }
  }

  // Load tasks from POD server
  Future<List<Task>> _loadServerTaskData() async {
    debugPrint('Starting to load tasks from POD...');
    
    final loggedIn = await loginIfRequired(context);
    if (!loggedIn) {
      throw Exception('Login required');
    }

    String webId = await getWebId() as String;
    debugPrint('WebID: $webId');
    
    webId = webId.replaceAll(profCard, '');
    debugPrint('Base WebID: $webId');

    // Use relative path for solidpod package
    final relativePath = '/solidtasks/data/$myTasksFile';
    final fullTaskFileUrl = '${webId}$relativePath';
    debugPrint('Task file URL: $fullTaskFileUrl');

    bool resExist = await _checkResourceStatus(fullTaskFileUrl);
    debugPrint('Resource exists: $resExist');
    
    if (!resExist) {
      debugPrint('Task file does not exist, returning empty list');
      return [];
    }

    String taskDataStr = await readPod(
      myTasksFile,  // Use relative path only
      context,
      widget,
    );

    debugPrint('Raw data from POD: ${taskDataStr.substring(0, taskDataStr.length > 200 ? 200 : taskDataStr.length)}...');

    if (taskDataStr.isEmpty) {
      return [];
    }

    try {
      // Try to parse as JSON first (for backwards compatibility)
      if (taskDataStr.trim().startsWith('[') || taskDataStr.trim().startsWith('{')) {
        final decodedData = json.decode(taskDataStr);
        List<Task> tasks = [];
        
        if (decodedData is List) {
          for (var taskJson in decodedData) {
            if (taskJson is Map<String, dynamic> && !taskJson.containsKey(updateTimeLabel)) {
              tasks.add(Task.fromJson(taskJson));
            }
          }
        }
        debugPrint('Loaded ${tasks.length} tasks from JSON format');
        return tasks;
      } else {
        // Parse as JSON embedded in Turtle format
        return _parseTasksFromTurtle(taskDataStr);
      }
    } catch (e) {
      debugPrint('Failed to parse task data: $e');
      throw Exception('Failed to parse task data: $e');
    }
  }

  // Parse tasks from Turtle format
  List<Task> _parseTasksFromTurtle(String turtleData) {
    try {
      debugPrint('Parsing turtle data...');
      // Look for data embedded in turtle
      final jsonStartIndex = turtleData.indexOf('[');
      final jsonEndIndex = turtleData.lastIndexOf(']');
      
      if (jsonStartIndex != -1 && jsonEndIndex != -1 && jsonEndIndex > jsonStartIndex) {
        final jsonStr = turtleData.substring(jsonStartIndex, jsonEndIndex + 1);
        debugPrint('Extracted JSON: $jsonStr');
        
        final decodedData = json.decode(jsonStr);
        List<Task> tasks = [];
        
        if (decodedData is List) {
          for (var taskJson in decodedData) {
            if (taskJson is Map<String, dynamic> && !taskJson.containsKey(updateTimeLabel)) {
              tasks.add(Task.fromJson(taskJson));
            }
          }
        }
        debugPrint('Loaded ${tasks.length} tasks from Turtle format');
        return tasks;
      }
      debugPrint('No JSON found in turtle data');
      return [];
    } catch (e) {
      debugPrint('Failed to parse turtle data: $e');
      return [];
    }
  }

  // Save tasks to POD server in Turtle format
  Future<void> _saveServerTaskData(List<Task> tasks) async {
    debugPrint('Starting to save tasks to POD...');
    
    final loggedIn = await loginIfRequired(context);
    if (!loggedIn) {
      throw Exception('Login required');
    }

    String webId = await getWebId() as String;
    debugPrint('WebID for saving: $webId');
    
    webId = webId.replaceAll(profCard, '');
    
    // Use relative path for directory operations
    final relativeDirPath = '/solidtasks/data/';
    final fullDirPath = '${webId}$relativeDirPath';
    debugPrint('Ensuring directory exists: $fullDirPath');
    
    try {
      await _ensureDirectoryExists(fullDirPath);
    } catch (e) {
      debugPrint('Failed to ensure directory exists: $e');
      // Continue anyway, might still work
    }

    // Create the JSON structure with timestamp
    List<Map<String, dynamic>> taskList = [
      {updateTimeLabel: DateTime.now().toIso8601String()}
    ];
    
    for (Task task in tasks) {
      taskList.add(task.toJson());
    }

    String taskJsonStr = json.encode(taskList);
    debugPrint('JSON to save: $taskJsonStr');

    // Simplified Turtle format - the issue might be with escaping quotes
    String turtleContent = '''@prefix : <#> .
@prefix solid: <http://www.w3.org/ns/solid/terms#> .
@prefix foaf: <http://xmlns.com/foaf/0.1/> .

:tasks a solid:Resource ;
    solid:content """$taskJsonStr""" .
''';

    debugPrint('Turtle content to save: ${turtleContent.substring(0, turtleContent.length > 300 ? 300 : turtleContent.length)}...');

    // Use RELATIVE path for writePod - the solidpod package handles the full URL construction
    final relativePath = '/solidtasks/data/$myTasksFile';
    debugPrint('Writing to relative path: $relativePath');

    final writeDataStatus = await writePod(
      myTasksFile,  // Use relative path only
      turtleContent,
      context,
      widget,
    );

    debugPrint('Write status: $writeDataStatus');

    if (writeDataStatus != SolidFunctionCallStatus.success) {
      throw Exception('Failed to save tasks to POD. Status: $writeDataStatus');
    }
    
    debugPrint('Successfully saved tasks to POD');
  }

  // Helper method to ensure directory exists
  Future<void> _ensureDirectoryExists(String dirPath) async {
    try {
      final dirExists = await _checkResourceStatus(dirPath, fileFlag: false);
      if (!dirExists) {
        debugPrint('Directory does not exist, attempting to create: $dirPath');
        // Try to create the directory structure
        await _createDirectory(dirPath);
      }
    } catch (e) {
      debugPrint('Error checking/creating directory: $e');
      rethrow;
    }
  }

  // Create directory in POD
  Future<void> _createDirectory(String dirPath) async {
    try {
      final (:accessToken, :dPopToken) = await getTokensForResource(dirPath, 'PUT');
      final response = await http.put(
        Uri.parse(dirPath),
        headers: <String, String>{
          'Content-Type': 'text/turtle',
          'Authorization': 'DPoP $accessToken',
          'Link': '<http://www.w3.org/ns/ldp#BasicContainer>; rel="type"',
          'DPoP': dPopToken,
        },
        body: '''@prefix ldp: <http://www.w3.org/ns/ldp#> .
<> a ldp:BasicContainer .
''',
      );

      if (response.statusCode != 201 && response.statusCode != 204) {
        debugPrint('Failed to create directory. Status: ${response.statusCode}, Body: ${response.body}');
        throw Exception('Failed to create directory: ${response.statusCode}');
      }
      debugPrint('Directory created successfully');
    } catch (e) {
      debugPrint('Error creating directory: $e');
      rethrow;
    }
  }

  // Check if a resource exists in the POD
  Future<bool> _checkResourceStatus(String resUrl, {bool fileFlag = true}) async {
    try {
      debugPrint('Checking resource status: $resUrl');
      final (:accessToken, :dPopToken) = await getTokensForResource(resUrl, 'GET');
      final response = await http.get(
        Uri.parse(resUrl),
        headers: <String, String>{
          'Content-Type': fileFlag ? 'text/turtle' : 'application/octet-stream',
          'Authorization': 'DPoP $accessToken',
          'Link': fileFlag
              ? '<http://www.w3.org/ns/ldp#Resource>; rel="type"'
              : '<http://www.w3.org/ns/ldp#BasicContainer>; rel="type"',
          'DPoP': dPopToken,
        },
      );

      debugPrint('Resource check response: ${response.statusCode}');
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) {
      debugPrint('Failed to check resource status: $e');
      return false;
    }
  }

  void _addTask() {
    if (_taskController.text.trim().isNotEmpty) {
      ref.read(tasksProvider.notifier).addTask(_taskController.text.trim());
      _taskController.clear();
      // Auto-save after adding task
      _saveTasksToPod();
    }
  }

  void _toggleTask(String id) {
    ref.read(tasksProvider.notifier).toggleTask(id);
    // Auto-save after toggling task
    _saveTasksToPod();
  }

  void _deleteTask(String id) {
    ref.read(tasksProvider.notifier).deleteTask(id);
    // Auto-save after deleting task
    _saveTasksToPod();
  }

  void _updateTask(String id, String newTitle, {DateTime? dueDate}) {
    ref.read(tasksProvider.notifier).updateTask(id, newTitle, dueDate: dueDate);
    // Auto-save after updating task
    _saveTasksToPod();
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(tasksProvider);
    final completedTasks = tasks.where((task) => task.isDone).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My To‑Do List'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          // Sync button
          IconButton(
            onPressed: _isSyncing ? null : _saveTasksToPod,
            icon: _isSyncing 
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            tooltip: 'Sync with POD',
          ),
          // Refresh button
          IconButton(
            onPressed: _isLoading ? null : _loadTasksFromPod,
            icon: _isLoading 
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            tooltip: 'Reload from POD',
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Center(
              child: Text(
                '$completedTasks/${tasks.length}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Add task section
          Container(
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
          ),
          // Tasks list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : tasks.isEmpty
                    ? const Center(
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
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(8.0),
                        itemCount: tasks.length,
                        itemBuilder: (context, index) {
                          final task = tasks[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4.0),
                            child: ListTile(
                              leading: Checkbox(
                                value: task.isDone,
                                onChanged: (_) => _toggleTask(task.id),
                              ),
                              title: Text(
                                task.title,
                                style: TextStyle(
                                  decoration: task.isDone ? TextDecoration.lineThrough : null,
                                  color: task.isDone ? Colors.grey : null,
                                ),
                              ),
                              subtitle: task.dueDate != null
                                  ? Text(
                                      'Due: ${task.dueDate!.day}/${task.dueDate!.month}/${task.dueDate!.year}',
                                      style: TextStyle(
                                        color: task.dueDate!.isBefore(DateTime.now()) 
                                            ? Colors.red 
                                            : Colors.grey[600],
                                      ),
                                    )
                                  : null,
                              trailing: PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'edit') {
                                    _showEditTaskDialog(task);
                                  } else if (value == 'delete') {
                                    _deleteTask(task.id);
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Row(
                                      children: [
                                        Icon(Icons.edit),
                                        SizedBox(width: 8),
                                        Text('Edit'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete, color: Colors.red),
                                        SizedBox(width: 8),
                                        Text('Delete', style: TextStyle(color: Colors.red)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  void _showEditTaskDialog(Task task) {
    final editController = TextEditingController(text: task.title);
    DateTime? selectedDate = task.dueDate;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Edit Task'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: editController,
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
                      selectedDate != null
                          ? 'Due: ${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}'
                          : 'No due date',
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: selectedDate ?? DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (date != null) {
                        setState(() {
                          selectedDate = date;
                        });
                      }
                    },
                    child: const Text('Set Date'),
                  ),
                  if (selectedDate != null)
                    TextButton(
                      onPressed: () {
                        setState(() {
                          selectedDate = null;
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
                if (editController.text.trim().isNotEmpty) {
                  _updateTask(
                    task.id,
                    editController.text.trim(),
                    dueDate: selectedDate,
                  );
                  Navigator.of(context).pop();
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
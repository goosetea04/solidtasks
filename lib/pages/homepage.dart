import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/tasks_provider.dart';
import '../services/pod_service.dart';
import '../services/pod_service_acp.dart';
import '../widgets/task_item.dart';
import '../widgets/weekly_calendar.dart';
import '../widgets/add_task_widget.dart';
import '../widgets/edit_task_dialog.dart';
import '../widgets/empty_state.dart';
import '../widgets/logout_dialog.dart';
import 'shared_tasks_page.dart';
import 'package:solidpod/solidpod.dart' show SharedResourcesUi, GrantPermissionUi;

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
  void _addTask(String title, String? description, DateTime? dueDate) {
    ref.read(tasksProvider.notifier).addTask(
      title,
      description: description,
      dueDate: dueDate,
    );
    _saveTasksToPod();
  }

  void _shareTask(String id) {
    PodService.openShareUiForTask(context, widget, id);
  }

  void _toggleTask(String id) {
    ref.read(tasksProvider.notifier).toggleTask(id);
    _saveTasksToPod();
  }

  void _deleteTask(String id) {
    ref.read(tasksProvider.notifier).deleteTask(id);
    _saveTasksToPod();
  }

  void _updateTask(String id, String newTitle, {String? description, DateTime? dueDate}) {
    ref.read(tasksProvider.notifier).updateTask(id, newTitle, description: description, dueDate: dueDate);
    _saveTasksToPod();
  }

  void _showEditTaskDialog(task) {
    showEditTaskDialog(
      context,
      task,
      (String title, String? description, DateTime? dueDate) {
        _updateTask(
          task.id,
          title,
          description: description, 
          dueDate: dueDate,
        );
      },
    );
  }

  // ACP Use Case Methods
  Future<void> _applyAcpUseCase(String taskId, String useCase) async {
    try {
      final taskUrl = await PodService.taskFileUrl(taskId);
      final ownerWebId = 'https://user.example.org/profile/card#me'; // Replace with actual user WebID

      switch (useCase) {
        case 'app_scoped':
          await _showAppScopedDialog(taskUrl, ownerWebId);
          break;
        case 'delegated_sharing':
          await _showDelegatedSharingDialog(taskUrl, ownerWebId);
          break;
        case 'time_limited':
          await _showTimeLimitedDialog(taskUrl, ownerWebId);
          break;
        case 'role_based':
          await _showRoleBasedDialog(taskUrl, ownerWebId);
          break;
      }
      
      _showSuccessSnackBar('ACP policy applied successfully!');
    } catch (e) {
      debugPrint('Error applying ACP use case: $e');
      _showErrorSnackBar('Failed to apply ACP policy: $e');
    }
  }

  Future<void> _showAppScopedDialog(String taskUrl, String ownerWebId) async {
    final readersController = TextEditingController();
    final clientIdController = TextEditingController(
      text: AcpService.officialClientId,
    );

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('App-Scoped Access'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Configure app-scoped access control:'),
            const SizedBox(height: 16),
            TextField(
              controller: readersController,
              decoration: const InputDecoration(
                labelText: 'Reader WebIDs (comma-separated)',
                hintText: 'https://alice.example.org/profile/card#me',
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: clientIdController,
              decoration: const InputDecoration(
                labelText: 'Allowed Client ID',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final readers = readersController.text.trim().isEmpty 
                  ? null 
                  : readersController.text.split(',').map((e) => e.trim()).toList();
              
              await AcpService.writeAppScopedAcr(
                taskUrl,
                ownerWebId,
                allowReadWebIds: readers,
                allowedClientId: clientIdController.text.trim(),
              );
              
              Navigator.pop(context);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  Future<void> _showDelegatedSharingDialog(String taskUrl, String ownerWebId) async {
    final managerController = TextEditingController();
    final contractorsController = TextEditingController();

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delegated Sharing'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Configure manager delegation:'),
            const SizedBox(height: 16),
            TextField(
              controller: managerController,
              decoration: const InputDecoration(
                labelText: 'Manager WebID',
                hintText: 'https://manager.example.org/profile/card#me',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: contractorsController,
              decoration: const InputDecoration(
                labelText: 'Contractor WebIDs (comma-separated)',
                hintText: 'https://contractor1.example.org/profile/card#me',
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final contractors = contractorsController.text.trim().isEmpty 
                  ? null 
                  : contractorsController.text.split(',').map((e) => e.trim()).toList();
              
              await AcpService.writeDelegatedSharingAcr(
                taskUrl,
                ownerWebId,
                managerController.text.trim(),
                contractorWebIds: contractors,
              );
              
              Navigator.pop(context);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  Future<void> _showTimeLimitedDialog(String taskUrl, String ownerWebId) async {
    final tempUsersController = TextEditingController();
    DateTime? selectedDate;

    return showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Time-Limited Access'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Configure temporary access:'),
              const SizedBox(height: 16),
              TextField(
                controller: tempUsersController,
                decoration: const InputDecoration(
                  labelText: 'Temporary User WebIDs (comma-separated)',
                  hintText: 'https://student1.example.org/profile/card#me',
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('Valid Until: '),
                  TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now().add(const Duration(days: 7)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setState(() {
                          selectedDate = picked;
                        });
                      }
                    },
                    child: Text(
                      selectedDate?.toString().split(' ')[0] ?? 'Select Date',
                      style: TextStyle(
                        color: selectedDate != null ? Colors.blue : Colors.grey,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final tempUsers = tempUsersController.text.trim().isEmpty 
                    ? null 
                    : tempUsersController.text.split(',').map((e) => e.trim()).toList();
                
                await AcpService.writeTimeLimitedAcr(
                  taskUrl,
                  ownerWebId,
                  tempAccessWebIds: tempUsers,
                  validUntil: selectedDate,
                );
                
                Navigator.pop(context);
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRoleBasedDialog(String taskUrl, String ownerWebId) async {
    final adminRolesController = TextEditingController();
    final reviewerRolesController = TextEditingController();
    final contributorRolesController = TextEditingController();
    final authorController = TextEditingController();

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Role-Based Access'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Configure role-based access:'),
              const SizedBox(height: 16),
              TextField(
                controller: adminRolesController,
                decoration: const InputDecoration(
                  labelText: 'Admin Roles (comma-separated)',
                  hintText: 'https://org.example.org/roles/admin',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: reviewerRolesController,
                decoration: const InputDecoration(
                  labelText: 'Reviewer Roles (comma-separated)',
                  hintText: 'https://org.example.org/roles/reviewer',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: contributorRolesController,
                decoration: const InputDecoration(
                  labelText: 'Contributor Roles (comma-separated)',
                  hintText: 'https://org.example.org/roles/contributor',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: authorController,
                decoration: const InputDecoration(
                  labelText: 'Resource Author WebID (optional)',
                  hintText: 'https://author.example.org/profile/card#me',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final adminRoles = adminRolesController.text.trim().isEmpty 
                  ? null 
                  : adminRolesController.text.split(',').map((e) => e.trim()).toList();
              final reviewerRoles = reviewerRolesController.text.trim().isEmpty 
                  ? null 
                  : reviewerRolesController.text.split(',').map((e) => e.trim()).toList();
              final contributorRoles = contributorRolesController.text.trim().isEmpty 
                  ? null 
                  : contributorRolesController.text.split(',').map((e) => e.trim()).toList();
              
              await AcpService.writeRoleBasedAcr(
                taskUrl,
                ownerWebId,
                adminRoles: adminRoles,
                reviewerRoles: reviewerRoles,
                contributorRoles: contributorRoles,
                resourceAuthor: authorController.text.trim().isEmpty 
                    ? null 
                    : authorController.text.trim(),
              );
              
              Navigator.pop(context);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  void _showAcpUseCasesDialog(String taskId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ACP Use Cases'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Choose an access control pattern:'),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.apps),
              title: const Text('App-Scoped Access'),
              subtitle: const Text('Only official client can write'),
              onTap: () {
                Navigator.pop(context);
                _applyAcpUseCase(taskId, 'app_scoped');
              },
            ),
            ListTile(
              leading: const Icon(Icons.supervisor_account),
              title: const Text('Delegated Sharing'),
              subtitle: const Text('Manager can grant limited access'),
              onTap: () {
                Navigator.pop(context);
                _applyAcpUseCase(taskId, 'delegated_sharing');
              },
            ),
            ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('Time-Limited Access'),
              subtitle: const Text('Temporary access with expiration'),
              onTap: () {
                Navigator.pop(context);
                _applyAcpUseCase(taskId, 'time_limited');
              },
            ),
            ListTile(
              leading: const Icon(Icons.groups),
              title: const Text('Role-Based Access'),
              subtitle: const Text('Access based on organizational roles'),
              onTap: () {
                Navigator.pop(context);
                _applyAcpUseCase(taskId, 'role_based');
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    // Show simple confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _isLoading = true;
      });

      try {
        // Clear all tasks from local state
        ref.read(tasksProvider.notifier).setTasks([]);
        
        // Logout from POD - this will handle navigation automatically
        final success = await PodService.logout(context);
        
        // Note: The code below might not execute if navigation happens immediately
        if (success && mounted) {
          _showSuccessSnackBar('Logged out successfully!');
        } else if (mounted) {
          _showErrorSnackBar('Error during logout. Please try again.');
        }
      } catch (e) {
        debugPrint('Logout error: $e');
        if (mounted) {
          _showErrorSnackBar('Logout failed: $e');
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
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

  Widget _buildAcpStatusChip(String acrContent) {
    final policies = <String>[];
    
    // Check for different ACP patterns
    if (acrContent.contains('ex:validUntil')) {
      policies.add('Time-Limited');
    }
    if (acrContent.contains('dct:creator')) {
      policies.add('Delegated');
    }
    if (acrContent.contains('anyOf ( <${AcpService.officialClientId}>')) {
      policies.add('App-Scoped');
    }
    if (acrContent.contains('/roles/')) {
      policies.add('Role-Based');
    }
    
    if (policies.isEmpty) {
      policies.add('Basic');
    }

    return Wrap(
      spacing: 4,
      children: policies.map((policy) => Chip(
        label: Text(policy, style: const TextStyle(fontSize: 10)),
        backgroundColor: Colors.blue[100],
        padding: const EdgeInsets.symmetric(horizontal: 4),
      )).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tasksNotifier = ref.watch(tasksProvider.notifier);
    final tasks = ref.watch(tasksProvider);

    // Get start of this week (Monday)
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Solid Tasks'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          // Shared resources button
          IconButton(
            tooltip: 'Shared tasks',
            icon: const Icon(Icons.group),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SharedTasksPage()),
              );
            },
          ),
          // Legacy shared resources button
          IconButton(
            tooltip: 'Shared with me',
            icon: const Icon(Icons.group),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SharedResourcesUi(
                    child: TodoHomePage(), // return destination
                  ),
                ),
              );
            },
          ),
          // Logout button
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
          ),
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Weekly calendar view
                WeeklyCalendar(tasks: tasks, weekStart: weekStart),
                const Divider(height: 1),

                // Task list
                Expanded(
                  child: tasks.isEmpty
                      ? const EmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
                          itemCount: tasks.length,
                          itemBuilder: (context, index) {
                            final task = tasks[index];

                            return Card(
                              child: Column(
                                children: [
                                  TaskItem(
                                    task: task,
                                    onToggle: () => _toggleTask(task.id),
                                    onDelete: () => _deleteTask(task.id),
                                    onEdit: () => _showEditTaskDialog(task),
                                    onShare: () => _shareTask(task.id),
                                  ),

                                  // Enhanced ACP info with use case buttons
                                  Container(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            const Text(
                                              'Access Control:',
                                              style: TextStyle(fontWeight: FontWeight.bold),
                                            ),
                                            ElevatedButton.icon(
                                              onPressed: () => _showAcpUseCasesDialog(task.id),
                                              icon: const Icon(Icons.security, size: 16),
                                              label: const Text('ACP', style: TextStyle(fontSize: 12)),
                                              style: ElevatedButton.styleFrom(
                                                minimumSize: const Size(60, 30),
                                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        
                                        // ACP Status Display
                                        FutureBuilder<String?>(
                                          future: PodService.taskFileUrl(task.id).then(
                                            (url) => AcpPresets.fetchAcr(url),
                                          ),
                                          builder: (context, snapshot) {
                                            if (snapshot.connectionState == ConnectionState.waiting) {
                                              return const Text("Loading ACP...");
                                            }
                                            if (!snapshot.hasData || snapshot.data == null) {
                                              return Row(
                                                children: [
                                                  const Text("No ACP found"),
                                                  const SizedBox(width: 8),
                                                  Chip(
                                                    label: const Text('Default', style: TextStyle(fontSize: 10)),
                                                    backgroundColor: Colors.grey[300],
                                                  ),
                                                ],
                                              );
                                            }

                                            final acr = snapshot.data!;
                                            final canRead = acr.contains('acl:Read');
                                            final canWrite = acr.contains('acl:Write');
                                            final canControl = acr.contains('acl:Control');

                                            return Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                // Permission chips
                                                Wrap(
                                                  spacing: 6,
                                                  children: [
                                                    Chip(
                                                      label: const Text("read", style: TextStyle(fontSize: 10)),
                                                      backgroundColor: canRead ? Colors.green[100] : Colors.grey[200],
                                                    ),
                                                    Chip(
                                                      label: const Text("write", style: TextStyle(fontSize: 10)),
                                                      backgroundColor: canWrite ? Colors.green[100] : Colors.grey[200],
                                                    ),
                                                    Chip(
                                                      label: const Text("control", style: TextStyle(fontSize: 10)),
                                                      backgroundColor: canControl ? Colors.green[100] : Colors.grey[200],
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 4),
                                                // ACP pattern chips
                                                Row(
                                                  children: [
                                                    const Text('Policy: ', style: TextStyle(fontSize: 12)),
                                                    _buildAcpStatusChip(acr),
                                                  ],
                                                ),
                                                // Time-limited access status
                                                if (acr.contains('ex:validUntil'))
                                                  FutureBuilder<bool>(
                                                    future: PodService.taskFileUrl(task.id)
                                                        .then((url) => AcpService.hasValidTimeAccess(url)),
                                                    builder: (context, timeSnapshot) {
                                                      if (!timeSnapshot.hasData) return const SizedBox.shrink();
                                                      final isValid = timeSnapshot.data!;
                                                      return Padding(
                                                        padding: const EdgeInsets.only(top: 4),
                                                        child: Row(
                                                          children: [
                                                            Icon(
                                                              isValid ? Icons.check_circle : Icons.warning,
                                                              size: 14,
                                                              color: isValid ? Colors.green : Colors.orange,
                                                            ),
                                                            const SizedBox(width: 4),
                                                            Text(
                                                              isValid ? 'Access valid' : 'Access expired',
                                                              style: TextStyle(
                                                                fontSize: 12,
                                                                color: isValid ? Colors.green : Colors.orange,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                    },
                                                  ),
                                              ],
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: AddTaskWidget(onAddTask: _addTask),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}
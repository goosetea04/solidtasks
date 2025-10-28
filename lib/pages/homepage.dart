import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/tasks_provider.dart';
import '../services/pod_service.dart';
import '../services/pod_service_acp.dart';
import '../services/sharing_service.dart';
import '../services/auth_service.dart';
import '../widgets/task_item.dart';
import '../widgets/weekly_calendar.dart';
import '../widgets/add_task_widget.dart';
import '../widgets/edit_task_dialog.dart';
import '../widgets/empty_state.dart';
import 'shared_tasks_page.dart';

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

  // Core operations
  Future<void> _loadTasksFromPod() async {
    await _executeWithLoading(() async {
      final tasks = await PodService.loadTasks(context, widget);
      ref.read(tasksProvider.notifier).setTasks(tasks);
    }, 'Failed to load tasks');
  }

  Future<void> _saveTasksToPod() async {
    await _executeWithSyncing(() async {
      final tasks = ref.read(tasksProvider);
      await PodService.saveTasks(tasks, context, widget);
      _showSnackBar('Tasks synced successfully!', Colors.green);
    }, 'Failed to sync tasks');
  }

  Future<void> _executeWithLoading(Future<void> Function() operation, String errorMsg) async {
    setState(() => _isLoading = true);
    try {
      await operation();
    } catch (e) {
      if (mounted) _showSnackBar('$errorMsg: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _executeWithSyncing(Future<void> Function() operation, String errorMsg) async {
    setState(() => _isSyncing = true);
    try {
      await operation();
    } catch (e) {
      if (mounted) _showSnackBar('$errorMsg: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  // Task operations
  void _addTask(String title, String? description, DateTime? dueDate) {
    ref.read(tasksProvider.notifier).addTask(title, description: description, dueDate: dueDate);
    _saveTasksToPod();
  }

  void _toggleTask(String id) {
    ref.read(tasksProvider.notifier).toggleTask(id);
    _saveTasksToPod();
  }

  Future<void> _deleteTask(String id) async {
    // First, delete the file from the server
    await _executeWithLoading(() async {
      final taskUrl = await PodService.taskFileUrl(id);
      await PodService.deleteTaskFile(taskUrl); // You need to add this method
      
      // Then remove from state
      ref.read(tasksProvider.notifier).deleteTask(id);
      _showSnackBar('Task deleted successfully!', Colors.green);
    }, 'Failed to delete task');
    _loadTasksFromPod(); // Refresh the list after deletion
  }

  void _updateTask(String id, String title, {String? description, DateTime? dueDate}) {
    ref.read(tasksProvider.notifier).updateTask(id, title, description: description, dueDate: dueDate);
    _saveTasksToPod();
  }

  void _shareTask(String id) => _showShareDialog(id);

  void _showShareDialog(String taskId) {
    final serverController = TextEditingController(text: 'pods.acp.solidcommunity.au');
    final usernameController = TextEditingController();
    final messageController = TextEditingController();
    String shareType = 'read';
    String acpPattern = 'basic';
    String constructedWebId = '';

    String buildWebId(String server, String username) {
      if (server.isEmpty || username.isEmpty) return '';
      return 'https://$server/$username/profile/card#me';
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          constructedWebId = buildWebId(serverController.text.trim(), usernameController.text.trim());
          
          return AlertDialog(
            title: const Text('Share Task'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Recipient Details:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: serverController,
                    decoration: const InputDecoration(
                      labelText: 'Server',
                      hintText: 'pods.acp.solidcommunity.au',
                      prefixIcon: Icon(Icons.dns),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: usernameController,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      hintText: 'acptest1',
                      prefixIcon: Icon(Icons.person),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  if (constructedWebId.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.link, size: 16, color: Colors.green),
                              SizedBox(width: 4),
                              Text('WebID:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            constructedWebId,
                            style: const TextStyle(fontSize: 11, color: Colors.black87),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    controller: messageController,
                    decoration: const InputDecoration(
                      labelText: 'Message (optional)',
                      hintText: 'Add a message...',
                      prefixIcon: Icon(Icons.message),
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  const Text('Permissions:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: shareType,
                    decoration: const InputDecoration(
                      labelText: 'Share Type',
                      prefixIcon: Icon(Icons.lock),
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'read', child: Text('Read Only')),
                      DropdownMenuItem(value: 'write', child: Text('Read & Write')),
                      DropdownMenuItem(value: 'control', child: Text('Full Control')),
                    ],
                    onChanged: (value) => setState(() => shareType = value!),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: acpPattern,
                    decoration: const InputDecoration(
                      labelText: 'Access Pattern',
                      prefixIcon: Icon(Icons.security),
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'basic', child: Text('Basic Sharing')),
                      DropdownMenuItem(value: 'app_scoped', child: Text('App-Scoped')),
                      DropdownMenuItem(value: 'delegated_sharing', child: Text('Delegated')),
                      DropdownMenuItem(value: 'role_based', child: Text('Role-Based')),
                    ],
                    onChanged: (value) => setState(() => acpPattern = value!),
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
                onPressed: constructedWebId.isEmpty ? null : () async {
                  await _shareTaskWithUser(taskId, constructedWebId, shareType, acpPattern, messageController.text.trim());
                  Navigator.pop(context);
                },
                child: const Text('Share'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _shareTaskWithUser(String taskId, String recipientWebId, String shareType, String pattern, String message) async {
    try {
      final taskUrl = await PodService.taskFileUrl(taskId);
      String? ownerWebId = await AuthService.getCurrentUserWebId();
      
      if (ownerWebId == null) {
        _showSnackBar('WebID is required to share tasks', Colors.orange);
        return;
      }
      
      if (!AuthService.isValidWebId(recipientWebId)) {
        _showSnackBar('Please enter a valid recipient WebID', Colors.red);
        return;
      }
      
      await SharingService.shareResourceWithUser(
        resourceUrl: taskUrl,
        ownerWebId: ownerWebId,
        recipientWebId: recipientWebId,
        shareType: shareType,
        message: message.isEmpty ? null : message,
        acpPattern: pattern,
      );
      
      _showSnackBar('Task shared successfully!', Colors.green);
    } catch (e) {
      _showSnackBar('Failed to share task: $e', Colors.red);
    }
  }

  void _showEditTaskDialog(task) {
    showEditTaskDialog(context, task, (title, description, dueDate) {
      _updateTask(task.id, title, description: description, dueDate: dueDate);
    });
  }

  // ACP operations
  Future<void> _applyAcpUseCase(String taskId, String useCase) async {
    try {
      final taskUrl = await PodService.taskFileUrl(taskId);
      String? ownerWebId = await AuthService.getCurrentUserWebId();
      
      if (ownerWebId == null) {
        _showSnackBar('WebID is required for ACP operations', Colors.orange);
        return;
      }

      switch (useCase) {
        case 'app_scoped': 
          await _showAcpDialog('App-Scoped Access', _buildAppScopedForm(taskUrl, ownerWebId));
        case 'delegated_sharing': 
          await _showAcpDialog('Delegated Sharing', _buildDelegatedForm(taskUrl, ownerWebId));
        case 'role_based': 
          await _showAcpDialog('Role-Based Access', _buildRoleBasedForm(taskUrl, ownerWebId));
        case 'container_inheritance':
          await _applyContainerInheritance(ownerWebId);
      }
      _showSnackBar('ACP policy applied successfully!', Colors.green);
    } catch (e) {
      _showSnackBar('Failed to apply ACP policy: $e', Colors.red);
    }
  }

  Widget _buildAppScopedForm(String taskUrl, String ownerWebId) {
    final readersCtrl = TextEditingController();
    final clientCtrl = TextEditingController(text: AcpService.officialClientId);
    
    return _AcpForm(
      children: [
        _buildTextField(readersCtrl, 'Reader WebIDs (comma-separated)', maxLines: 2),
        _buildTextField(clientCtrl, 'Allowed Client ID'),
      ],
      onApply: () async {
        final readers = _parseWebIds(readersCtrl.text);
        await AcpService.writeAppScopedAcr(taskUrl, ownerWebId, 
          allowReadWebIds: readers, allowedClientId: clientCtrl.text.trim());
      },
    );
  }

  Widget _buildDelegatedForm(String taskUrl, String ownerWebId) {
    final managerCtrl = TextEditingController();
    final contractorsCtrl = TextEditingController();
    
    return _AcpForm(
      children: [
        _buildTextField(managerCtrl, 'Manager WebID'),
        _buildTextField(contractorsCtrl, 'Contractor WebIDs (comma-separated)', maxLines: 2),
      ],
      onApply: () async {
        final contractors = _parseWebIds(contractorsCtrl.text);
        await AcpService.writeDelegatedSharingAcr(taskUrl, ownerWebId, 
          managerCtrl.text.trim(), contractorWebIds: contractors);
      },
    );
  }

  Widget _buildRoleBasedForm(String taskUrl, String ownerWebId) {
    final adminCtrl = TextEditingController();
    final reviewerCtrl = TextEditingController();
    final contributorCtrl = TextEditingController();
    
    return _AcpForm(
      children: [
        _buildTextField(adminCtrl, 'Admin WebIDs (comma-separated)'),
        _buildTextField(reviewerCtrl, 'Reviewer WebIDs (comma-separated)'),
        _buildTextField(contributorCtrl, 'Contributor WebIDs (comma-separated)'),
      ],
      onApply: () async {
        await AcpService.writeRoleBasedAcr(taskUrl, ownerWebId,
          adminWebIds: _parseWebIds(adminCtrl.text),
          reviewerWebIds: _parseWebIds(reviewerCtrl.text),
          contributorWebIds: _parseWebIds(contributorCtrl.text),
        );
      },
    );
  }

  Future<void> _applyContainerInheritance(String ownerWebId) async {
    final readCtrl = TextEditingController();
    final writeCtrl = TextEditingController();
    
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Container Inheritance'),
        content: _AcpForm(
          children: [
            const Text('Apply default permissions to all tasks in the container:'),
            const SizedBox(height: 8),
            _buildTextField(readCtrl, 'Default Read Access WebIDs', maxLines: 2),
            _buildTextField(writeCtrl, 'Default Write Access WebIDs', maxLines: 2),
          ],
          onApply: () async {
            final webId = ownerWebId.replaceAll('/profile/card#me', '');
            final containerUrl = '$webId/solidtasks/data/';
            await AcpService.writeContainerAcr(
              containerUrl,
              ownerWebId,
              defaultReadWebIds: _parseWebIds(readCtrl.text),
              defaultWriteWebIds: _parseWebIds(writeCtrl.text),
            );
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ],
      ),
    );
  }

  Future<void> _showAcpDialog(String title, Widget form) {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: form,
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ],
      ),
    );
  }

  void _showAcpUseCasesDialog(String taskId) {
    final useCases = [
      ('App-Scoped Access', 'Only official client can write', Icons.apps, 'app_scoped'),
      ('Delegated Sharing', 'Manager can grant limited access', Icons.supervisor_account, 'delegated_sharing'),
      ('Role-Based Access', 'Access based on organizational roles', Icons.groups, 'role_based'),
      ('Container Inheritance', 'Apply default permissions to all tasks', Icons.folder_shared, 'container_inheritance'),
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ACP Use Cases'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Choose an access control pattern:'),
            const SizedBox(height: 16),
            ...useCases.map((useCase) => ListTile(
              leading: Icon(useCase.$3),
              title: Text(useCase.$1),
              subtitle: Text(useCase.$2),
              onTap: () {
                Navigator.pop(context);
                _applyAcpUseCase(taskId, useCase.$4);
              },
            )),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
      ),
    );
  }

  Future<void> _logout() async {
    final confirmed = await _showConfirmDialog('Logout', 'Are you sure you want to logout?');
    if (!confirmed) return;

    await _executeWithLoading(() async {
      ref.read(tasksProvider.notifier).setTasks([]);
      final success = await PodService.logout(context);
      if (success && mounted) _showSnackBar('Logged out successfully!', Colors.green);
      else if (mounted) _showSnackBar('Error during logout. Please try again.', Colors.red);
    }, 'Logout failed');
  }

  // UI Helpers
  Widget _buildTextField(TextEditingController controller, String label, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
        maxLines: maxLines,
      ),
    );
  }

  List<String>? _parseWebIds(String text) {
    return text.trim().isEmpty ? null : text.split(',').map((e) => e.trim()).toList();
  }

  Future<bool> _showConfirmDialog(String title, String content) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Confirm'),
          ),
        ],
      ),
    ) ?? false;
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  Widget _buildLoadingIndicator() => const SizedBox(
    width: 20, height: 20,
    child: CircularProgressIndicator(strokeWidth: 2),
  );

  Widget _buildAcpStatusDisplay(String taskId) {
    return FutureBuilder<String?>(
      future: PodService.taskFileUrl(taskId).then((url) => AcpPresets.fetchAcr(url)),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Text("Loading ACP...");
        }
        
        if (!snapshot.hasData || snapshot.data == null) {
          return const Row(
            children: [
              Text("No ACP found"),
              SizedBox(width: 8),
              Chip(label: Text('Default', style: TextStyle(fontSize: 10))),
            ],
          );
        }

        final acr = snapshot.data!;
        final permissions = ['read', 'write', 'control']
            .where((p) => acr.contains('acl:${p.capitalize()}'))
            .map((p) => Chip(
              label: Text(p, style: const TextStyle(fontSize: 10)),
              backgroundColor: Colors.green[100],
            )).toList();

        final policies = _extractPolicies(acr);
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(spacing: 6, children: permissions),
            const SizedBox(height: 4),
            Row(
              children: [
                const Text('Pattern: ', style: TextStyle(fontSize: 12)),
                ..._buildPolicyChips(policies),
              ],
            ),
          ],
        );
      },
    );
  }

  List<String> _extractPolicies(String acr) {
    final policies = <String>[];
    if (acr.contains('dct:creator')) policies.add('Delegated');
    if (acr.contains('acp:client')) policies.add('App-Scoped');
    if (acr.contains('adminMatcher') || acr.contains('reviewerMatcher')) policies.add('Role-Based');
    return policies.isEmpty ? ['Basic'] : policies;
  }

  List<Widget> _buildPolicyChips(List<String> policies) {
    return policies.map((policy) => Chip(
      label: Text(policy, style: const TextStyle(fontSize: 10)),
      backgroundColor: Colors.blue[100],
    )).toList();
  }

  @override
  Widget build(BuildContext context) {
    final tasksNotifier = ref.watch(tasksProvider.notifier);
    final tasks = ref.watch(tasksProvider);
    final weekStart = DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Solid Tasks'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.group),
            tooltip: 'Shared tasks',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SharedTasksPage())),
          ),
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout), tooltip: 'Logout'),
          IconButton(
            onPressed: _isSyncing ? null : _saveTasksToPod,
            icon: _isSyncing ? _buildLoadingIndicator() : const Icon(Icons.sync),
            tooltip: 'Save Changes to POD',
          ),
          IconButton(
            onPressed: _isLoading ? null : _loadTasksFromPod,
            icon: _isLoading ? _buildLoadingIndicator() : const Icon(Icons.refresh),
            tooltip: 'Reload Data from POD',
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Center(
              child: Text('${tasksNotifier.completedCount}/${tasksNotifier.totalCount}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                WeeklyCalendar(tasks: tasks, initialWeekStart: weekStart),
                const Divider(height: 1),
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
                                  Container(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            const Text('Access Control:', style: TextStyle(fontWeight: FontWeight.bold)),
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
                                        _buildAcpStatusDisplay(task.id),
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

class _AcpForm extends StatelessWidget {
  final List<Widget> children;
  final Future<void> Function() onApply;

  const _AcpForm({required this.children, required this.onApply});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...children,
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            ElevatedButton(
              onPressed: () async {
                await onApply();
                Navigator.pop(context);
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ],
    );
  }
}

extension StringExtension on String {
  String capitalize() => '${this[0].toUpperCase()}${substring(1)}';
}
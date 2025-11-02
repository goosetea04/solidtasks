import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../services/sharing_service.dart';
import '../services/permission_log_service.dart';
import '../services/pod_service.dart';
import '../services/auth_service.dart';
import '../models/task.dart';
import 'package:solidpod/solidpod.dart';

class SharedTasksPage extends ConsumerStatefulWidget {
  const SharedTasksPage({Key? key}) : super(key: key);

  @override
  ConsumerState<SharedTasksPage> createState() => _SharedTasksPageState();
}

class _SharedTasksPageState extends ConsumerState<SharedTasksPage> {
  List<PermissionLogEntry> _sharedLogs = [];
  bool _isLoading = false;
  String? _currentUserWebId;

  @override
  void initState() {
    super.initState();
    _loadSharedTasks();
  }

  Future<void> _loadSharedTasks() async {
    setState(() => _isLoading = true);
    
    try {
      // Check authentication first
      final isAuthenticated = await AuthService.isAuthenticated();
      if (!isAuthenticated) {
        _showSnackBar('Please log in to view shared tasks', Colors.orange);
        return;
      }

      // Get current user WebID
      _currentUserWebId = await AuthService.getCurrentUserWebId();
      
      if (_currentUserWebId == null && mounted) {
        debugPrint('getWebId() returned null, prompting user for WebID');
        _currentUserWebId = await WebIdDialogs.promptForWebId(context);
      }
      
      if (_currentUserWebId != null) {
        debugPrint('(checking) Loading shared resources from permission logs for: $_currentUserWebId');
        
        // Load from permission logs instead of inbox
        final allLogs = await PermissionLogService.fetchUserLogs();
        debugPrint('(logging) Total logs fetched: ${allLogs.length}');
        
        // Filter for shares where current user is the recipient
        _sharedLogs = allLogs.where((log) {
          final isRecipient = log.recipientWebId == _currentUserWebId;
          final isGrant = log.permissionType == 'grant';
          debugPrint('   Log ${log.id}: recipient=${log.recipientWebId}, isRecipient=$isRecipient, isGrant=$isGrant');
          return isRecipient && isGrant;
        }).toList();
        
        setState(() {});
        
        if (_sharedLogs.isEmpty) {
          debugPrint('(fail) No shared resources found in logs');
        } else {
          debugPrint('(check) Found ${_sharedLogs.length} shared resources');
          for (final log in _sharedLogs) {
            debugPrint('   - ${log.resourceUrl} from ${log.granterWebId}');
          }
        }
      } else {
        _showSnackBar('WebID is required to view shared tasks', Colors.red);
      }
    } catch (e) {
      debugPrint('(fail) Error loading shared tasks: $e');
      _showSnackBar('Failed to load shared tasks: $e', Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<Task?> _loadTaskFromResource(PermissionLogEntry logEntry) async {
    try {
      debugPrint('🔄 Attempting to load task from: ${logEntry.resourceUrl}');
      
      final (:accessToken, :dPopToken) = await getTokensForResource(logEntry.resourceUrl, 'GET');
      final response = await http.get(
        Uri.parse(logEntry.resourceUrl),
        headers: {
          'Accept': 'application/ld+json, text/turtle',
          'Authorization': 'DPoP $accessToken',
          'DPoP': dPopToken,
        },
      );

      debugPrint('   Response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        debugPrint('   (check) Task loaded successfully');
        return _parseTaskFromRdf(response.body, logEntry.resourceUrl);
      } else {
        debugPrint('   (fail) Failed to load task: ${response.statusCode}');
        debugPrint('   Response: ${response.body}');
      }
    } catch (e) {
      debugPrint('(fail) Error loading task from ${logEntry.resourceUrl}: $e');
    }
    return null;
  }

  Task _parseTaskFromRdf(String content, String resourceUrl) {
    // Simplified parsing - in production, use proper RDF library
    final idMatch = RegExp(r'"id":\s*"([^"]+)"').firstMatch(content);
    final titleMatch = RegExp(r'"title":\s*"([^"]+)"').firstMatch(content);
    final completedMatch = RegExp(r'"completed":\s*(true|false)').firstMatch(content);
    
    return Task(
      id: idMatch?.group(1) ?? resourceUrl.split('/').last,
      title: titleMatch?.group(1) ?? 'Shared Task',
      isDone: completedMatch?.group(1) == 'true',
      description: null,
      dueDate: null,
      createdAt: DateTime.now(),
    );
  }

  Future<void> _acceptShare(PermissionLogEntry logEntry) async {
    try {
      debugPrint('(searching) Testing access to: ${logEntry.resourceUrl}');
      
      final canAccess = await SharingService.canAccessResource(
        logEntry.resourceUrl, 
        _currentUserWebId!
      );
      
      if (canAccess) {
        debugPrint('(check) Access confirmed!');
        _showSnackBar('Task is accessible!', Colors.green);
        await _addToLocalTasks(logEntry);
      } else {
        debugPrint('(fail) Access denied');
        _showSnackBar('Access denied to task', Colors.red);
      }
    } catch (e) {
      debugPrint('(fail) Error testing access: $e');
      _showSnackBar('Error testing access: $e', Colors.red);
    }
  }

  Future<void> _addToLocalTasks(PermissionLogEntry logEntry) async {
    try {
      final task = await _loadTaskFromResource(logEntry);
      if (task != null) {
        // Add to local state
        _showSnackBar('Task added to your list', Colors.green);
        debugPrint('(check) Task added: ${task.title}');
      } else {
        _showSnackBar('Could not load task data', Colors.red);
      }
    } catch (e) {
      debugPrint('(fail) Failed to add task locally: $e');
      _showSnackBar('Failed to add task locally: $e', Colors.red);
    }
  }

  Future<void> _declineShare(PermissionLogEntry logEntry) async {
    setState(() {
      _sharedLogs.removeWhere((l) => l.id == logEntry.id);
    });
    _showSnackBar('Share declined', Colors.orange);
  }

  Future<void> _openTask(PermissionLogEntry logEntry) async {
    try {
      debugPrint('(searching) Opening task: ${logEntry.resourceUrl}');
      
      final canAccess = await SharingService.canAccessResource(
        logEntry.resourceUrl, 
        _currentUserWebId!
      );
      
      if (!canAccess) {
        _showSnackBar('No access to this task', Colors.red);
        return;
      }

      final task = await _loadTaskFromResource(logEntry);
      if (task != null) {
        _showTaskDialog(task, logEntry);
      } else {
        _showSnackBar('Could not load task data', Colors.red);
      }
    } catch (e) {
      debugPrint('(fail) Error opening task: $e');
      _showSnackBar('Error opening task: $e', Colors.red);
    }
  }

  void _showTaskDialog(Task task, PermissionLogEntry logEntry) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Shared Task: ${task.title}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Shared by: ${_extractName(logEntry.granterWebId)}'),
            Text('Permission: ${logEntry.permissions.join(", ")}'),
            Text('Shared: ${_formatDate(logEntry.timestamp)}'),
            Text('Pattern: ${logEntry.acpPattern}'),
            const Divider(),
            Text('Task Status: ${task.isDone ? 'Completed ✓' : 'Pending'}'),
            if (task.description != null)
              Text('Description: ${task.description}'),
            if (task.dueDate != null)
              Text('Due: ${task.dueDate.toString().split(' ')[0]}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (logEntry.permissions.contains('write') || logEntry.permissions.contains('control'))
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _addToLocalTasks(logEntry);
              },
              child: const Text('Add to My Tasks'),
            ),
        ],
      ),
    );
  }

  Widget _buildTaskCard(PermissionLogEntry logEntry) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.task_alt, color: Colors.blue[700]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Task: ${logEntry.resourceUrl.split('/').last.replaceAll('.ttl', '')}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _buildPermissionChip(logEntry.permissions),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.person, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text('From: ${_extractName(logEntry.granterWebId)}'),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.schedule, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text('Shared: ${_formatDate(logEntry.timestamp)}'),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.security, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text('Pattern: ${logEntry.acpPattern}'),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _declineShare(logEntry),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Decline'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _openTask(logEntry),
                  icon: const Icon(Icons.visibility, size: 18),
                  label: const Text('View'),
                ),
                ElevatedButton.icon(
                  onPressed: () => _acceptShare(logEntry),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Accept'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionChip(List<String> permissions) {
    Color color;
    IconData icon;
    String label;
    
    if (permissions.contains('control')) {
      color = Colors.red;
      icon = Icons.admin_panel_settings;
      label = 'Full Access';
    } else if (permissions.contains('write')) {
      color = Colors.orange;
      icon = Icons.edit;
      label = 'Can Edit';
    } else if (permissions.contains('read')) {
      color = Colors.blue;
      icon = Icons.visibility;
      label = 'View Only';
    } else {
      color = Colors.grey;
      icon = Icons.help;
      label = 'Unknown';
    }

    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      backgroundColor: color.withOpacity(0.1),
      side: BorderSide(color: color.withOpacity(0.3)),
      avatar: Icon(icon, size: 16, color: color),
    );
  }

  String _extractName(String webId) {
    final uri = Uri.tryParse(webId);
    if (uri != null) {
      // Extract pod name from URL
      final pathSegments = uri.pathSegments;
      if (pathSegments.isNotEmpty) {
        return pathSegments.first.toUpperCase();
      }
      return uri.host.split('.').first.toUpperCase();
    }
    return webId;
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inMinutes}m ago';
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shared Tasks'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadSharedTasks,
            icon: _isLoading 
              ? const SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _sharedLogs.isEmpty
              ? _buildEmptyState()
              : Column(
                  children: [
                    _buildHeader(),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _sharedLogs.length,
                        itemBuilder: (context, index) {
                          return _buildTaskCard(_sharedLogs[index]);
                        },
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.share, color: Theme.of(context).primaryColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_sharedLogs.length} task${_sharedLogs.length == 1 ? '' : 's'} shared with you',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'From permission logs',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inbox,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No shared tasks',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tasks shared with you will appear here',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadSharedTasks,
            icon: const Icon(Icons.refresh),
            label: const Text('Check for Shares'),
          ),
          const SizedBox(height: 16),
          if (_currentUserWebId != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Checking logs for:\n${_extractName(_currentUserWebId!)}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[500],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
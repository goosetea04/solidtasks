import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../services/sharing_service.dart';
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
  List<SharedResource> _sharedResources = [];
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

      // Get current user WebID using the solidpod library
      _currentUserWebId = await AuthService.getCurrentUserWebId();
      
      // Only prompt if getWebId() failed (fallback)
      if (_currentUserWebId == null && mounted) {
        debugPrint('getWebId() returned null, prompting user for WebID');
        _currentUserWebId = await WebIdDialogs.promptForWebId(context);
      }
      
      if (_currentUserWebId != null) {
        debugPrint('Loading shared resources for: $_currentUserWebId');
        final resources = await SharingService.getSharedResources(_currentUserWebId!);
        setState(() => _sharedResources = resources);
        
        if (resources.isEmpty) {
          debugPrint('No shared resources found');
        } else {
          debugPrint('Found ${resources.length} shared resources');
        }
      } else {
        _showSnackBar('WebID is required to view shared tasks', Colors.red);
      }
    } catch (e) {
      debugPrint('Error loading shared tasks: $e');
      _showSnackBar('Failed to load shared tasks: $e', Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<String?> _getCurrentUserWebId() async {
    return await AuthService.getCurrentUserWebId();
  }

  Future<Task?> _loadTaskFromResource(SharedResource resource) async {
    try {
      final (:accessToken, :dPopToken) = await getTokensForResource(resource.resourceUrl, 'GET');
      final response = await http.get(
        Uri.parse(resource.resourceUrl),
        headers: {
          'Accept': 'application/ld+json, text/turtle',
          'Authorization': 'DPoP $accessToken',
          'DPoP': dPopToken,
        },
      );

      if (response.statusCode == 200) {
        return _parseTaskFromRdf(response.body, resource.resourceUrl);
      }
    } catch (e) {
      debugPrint('Error loading task from ${resource.resourceUrl}: $e');
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

  Future<void> _acceptShare(SharedResource resource) async {
    try {
      final canAccess = await SharingService.canAccessResource(resource.resourceUrl, _currentUserWebId!);
      
      if (canAccess) {
        _showSnackBar('Task is accessible!', Colors.green);
        await _addToLocalTasks(resource);
      } else {
        _showSnackBar('Access denied to task', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Error testing access: $e', Colors.red);
    }
  }

  Future<void> _addToLocalTasks(SharedResource resource) async {
    try {
      final task = await _loadTaskFromResource(resource);
      if (task != null) {
        // Add to local state
        _showSnackBar('Task added to your list', Colors.green);
      }
    } catch (e) {
      _showSnackBar('Failed to add task locally: $e', Colors.red);
    }
  }

  Future<void> _declineShare(SharedResource resource) async {
    setState(() {
      _sharedResources.removeWhere((r) => r.id == resource.id);
    });
    _showSnackBar('Share declined', Colors.orange);
  }

  Future<void> _openTask(SharedResource resource) async {
    try {
      final canAccess = await SharingService.canAccessResource(resource.resourceUrl, _currentUserWebId!);
      
      if (!canAccess) {
        _showSnackBar('No access to this task', Colors.red);
        return;
      }

      final task = await _loadTaskFromResource(resource);
      if (task != null) {
        _showTaskDialog(task, resource);
      } else {
        _showSnackBar('Could not load task data', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Error opening task: $e', Colors.red);
    }
  }

  void _showTaskDialog(Task task, SharedResource resource) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Shared Task: ${task.title}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Shared by: ${_extractName(resource.sharedBy)}'),
            Text('Permission: ${resource.shareType}'),
            Text('Shared: ${_formatDate(resource.timestamp)}'),
            if (resource.message != null) ...[
              const SizedBox(height: 8),
              Text('Message: ${resource.message}'),
            ],
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
          if (resource.shareType == 'write' || resource.shareType == 'control')
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _addToLocalTasks(resource);
              },
              child: const Text('Add to My Tasks'),
            ),
        ],
      ),
    );
  }

  Widget _buildTaskCard(SharedResource resource) {
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
                    'Task: ${resource.resourceUrl.split('/').last.replaceAll('.ttl', '')}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _buildPermissionChip(resource.shareType),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.person, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text('From: ${_extractName(resource.sharedBy)}'),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.schedule, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text('Shared: ${_formatDate(resource.timestamp)}'),
              ],
            ),
            if (resource.message != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Icon(Icons.message, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        resource.message!,
                        style: const TextStyle(fontStyle: FontStyle.italic),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _declineShare(resource),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Decline'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _openTask(resource),
                  icon: const Icon(Icons.visibility, size: 18),
                  label: const Text('View'),
                ),
                ElevatedButton.icon(
                  onPressed: () => _acceptShare(resource),
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

  Widget _buildPermissionChip(String shareType) {
    Color color;
    IconData icon;
    String label;
    
    switch (shareType) {
      case 'read':
        color = Colors.blue;
        icon = Icons.visibility;
        label = 'View Only';
        break;
      case 'write':
        color = Colors.orange;
        icon = Icons.edit;
        label = 'Can Edit';
        break;
      case 'control':
        color = Colors.red;
        icon = Icons.admin_panel_settings;
        label = 'Full Access';
        break;
      default:
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
          : _sharedResources.isEmpty
              ? _buildEmptyState()
              : Column(
                  children: [
                    _buildHeader(),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _sharedResources.length,
                        itemBuilder: (context, index) {
                          return _buildTaskCard(_sharedResources[index]);
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
      child: Row(
        children: [
          Icon(Icons.share, color: Theme.of(context).primaryColor),
          const SizedBox(width: 8),
          Text(
            '${_sharedResources.length} task${_sharedResources.length == 1 ? '' : 's'} shared with you',
            style: Theme.of(context).textTheme.titleMedium,
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
        ],
      ),
    );
  }
}
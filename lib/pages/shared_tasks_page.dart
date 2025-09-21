import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:solidpod/solidpod.dart';
import '../models/task.dart';
import '../services/pod_service.dart';
import '../services/pod_service_acp.dart';
import '../models/sharedEntry.dart';

/// Lists resources shared to the current WebID and lets you open/edit
class SharedTasksPage extends StatefulWidget {
  const SharedTasksPage({Key? key}) : super(key: key);

  @override
  State<SharedTasksPage> createState() => _SharedTasksPageState();
}

class _SharedTasksPageState extends State<SharedTasksPage> {
  bool _loading = true;
  String? _error;
  List<SharedEntry> _items = [];

  @override
  void initState() {
    super.initState();
    _loadSharedList();
  }

  Future<void> _loadSharedList() async {
    setState(() {
      _loading = true;
      _error = null;
      _items = [];
    });

    try {
      // Programmatically fetch "shared with me" resources.
      final res = await sharedResources(context, widget);
      if (res is Map) {
        final entries = <SharedEntry>[];
        res.forEach((k, v) {
          try {
            final url = k as String;
            final owner = v[PermissionLogLiteral.owner] as String? ?? '';
            final perms = (v[PermissionLogLiteral.permissions] as String? ?? '').toLowerCase();
            entries.add(SharedEntry(
              url: url,
              ownerWebId: owner,
              permissionsRaw: perms,
              // Lightweight hinting for "tasks"
              isLikelyTask: url.endsWith('.ttl') && url.contains('task_'),
            ));
          } catch (_) {
            // ignore malformed rows
          }
        });
        entries.sort((a, b) => a.name.compareTo(b.name));
        setState(() => _items = entries);
      } else {
        setState(() => _error = 'Could not load shared resources.');
      }
    } catch (e) {
      setState(() => _error = 'Load failed: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shared with me'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadSharedList,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _items.isEmpty
                  ? const Center(child: Text('No shared files found.'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final it = _items[i];
                        final canRead = it.permissionsRaw.contains('read');
                        final canWrite = it.permissionsRaw.contains('write');
                        final canAppend = it.permissionsRaw.contains('append');
                        final canControl = it.permissionsRaw.contains('control');

                        return ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: it.isLikelyTask
                                  ? Theme.of(context).colorScheme.primary.withOpacity(0.25)
                                  : Theme.of(context).dividerColor,
                            ),
                          ),
                          leading: Icon(
                            it.isLikelyTask ? Icons.checklist_rtl : Icons.description,
                          ),
                          title: Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(it.url, maxLines: 1, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 6),
                              // --- FIXED: Use AcpService.fetchAcr instead of PodServiceAcp.fetchAcr ---
                              FutureBuilder<String?>(
                                future: AcpPresets.fetchAcr(it.url), // Fixed this line
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState == ConnectionState.waiting) {
                                    return const Text("Loading ACP...");
                                  }
                                  if (!snapshot.hasData || snapshot.data == null) {
                                    // fallback to existing WAC perms if no ACP found
                                    return Wrap(
                                      spacing: 6,
                                      runSpacing: -6,
                                      children: [
                                        _permChip('read', canRead),
                                        _permChip('write', canWrite),
                                        _permChip('append', canAppend),
                                        _permChip('control', canControl),
                                      ],
                                    );
                                  }
                                  final acr = snapshot.data!;
                                  final canReadACP = acr.contains('acl:Read');
                                  final canWriteACP = acr.contains('acl:Write');
                                  final canControlACP = acr.contains('acl:Control');

                                  return Wrap(
                                    spacing: 6,
                                    runSpacing: -6,
                                    children: [
                                      _permChip('read', canReadACP),
                                      _permChip('write', canWriteACP),
                                      _permChip('control', canControlACP),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                          onTap: canRead
                              ? () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => _SharedTaskEditorPage(
                                        resourceUrl: it.url,
                                        ownerWebId: it.ownerWebId,
                                        canWrite: canWrite,
                                      ),
                                    ),
                                  );
                                }
                              : () => _snack('You do not have read permission for this resource.'),
                        );
                      },
                    ),
    );
  }

  Widget _permChip(String label, bool on) => Chip(
        label: Text(label),
        visualDensity: VisualDensity.compact,
        side: BorderSide(color: on ? Colors.green : Colors.grey),
        backgroundColor: on ? Colors.green.withOpacity(0.12) : null,
      );

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

/// Editor for a single shared task_<id>.ttl.
class _SharedTaskEditorPage extends StatefulWidget {
  final String resourceUrl;
  final String ownerWebId;
  final bool canWrite;

  const _SharedTaskEditorPage({
    Key? key,
    required this.resourceUrl,
    required this.ownerWebId,
    required this.canWrite,
  }) : super(key: key);

  @override
  State<_SharedTaskEditorPage> createState() => _SharedTaskEditorPageState();
}

class _SharedTaskEditorPageState extends State<_SharedTaskEditorPage> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  Task? _task;

  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  DateTime? _dueDate;
  bool _isDone = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _task = null;
    });

    try {
      // solidpod reads (and decrypts if needed) external resource by URL
      final content = await readExternalPod(widget.resourceUrl, context, widget);
      if (content == null) {
        setState(() => _error = 'Resource not found.');
        return;
      }

      final decoded = _extractJsonFromTtl(content as String? ?? '');
      if (decoded == null) {
        setState(() => _error = 'Could not parse task JSON from TTL.');
        return;
      }

      Task t;
      if (decoded is List && decoded.isNotEmpty && decoded.first is Map<String, dynamic>) {
        t = Task.fromJson(Map<String, dynamic>.from(decoded.first));
      } else if (decoded is Map<String, dynamic>) {
        t = Task.fromJson(decoded);
      } else {
        setState(() => _error = 'Unsupported JSON structure.');
        return;
      }

      _task = t;
      _titleCtrl.text = t.title;
      _descCtrl.text = t.description ?? '';
      _dueDate = t.dueDate;
      _isDone = t.isDone;
      setState(() {});
    } catch (e) {
      setState(() => _error = 'Load failed: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_canEdit()) return;
    if (_task == null) return;

    setState(() => _saving = true);

    try {
      final updated = _task!.copyWith(
        title: _titleCtrl.text.trim(),
        dueDate: _dueDate,
        isDone: _isDone,
        description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      );

      final ttl = _taskToTurtle(updated);

      // Use solidpod to write back to an external POD (owner is needed).
      final status = await writeExternalPod(
        widget.resourceUrl,
        ttl,
        widget.ownerWebId,
        context,
        widget,
      );

      if (!mounted) return;

      if (status == SolidFunctionCallStatus.success) {
        _task = updated;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $status')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool _canEdit() => widget.canWrite;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(Uri.parse(widget.resourceUrl).pathSegments.last),
        actions: [
          if (_canEdit())
            IconButton(
              tooltip: 'Save',
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              onPressed: _saving ? null : _save,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _task == null
                  ? const SizedBox.shrink()
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        TextField(
                          controller: _titleCtrl,
                          decoration: const InputDecoration(labelText: 'Title'),
                          enabled: _canEdit(),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _descCtrl,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'Description',
                            hintText: 'Optional details about this task',
                            border: OutlineInputBorder(),
                          ),
                          enabled: _canEdit(),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Checkbox(
                              value: _isDone,
                              onChanged: _canEdit()
                                  ? (v) => setState(() => _isDone = v ?? false)
                                  : null,
                            ),
                            const Text('Completed'),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _dueDate == null
                                    ? 'No due date'
                                    : 'Due: ${_dueDate!.day}/${_dueDate!.month}/${_dueDate!.year}',
                              ),
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.event),
                              label: const Text('Pick date'),
                              onPressed: _canEdit()
                                  ? () async {
                                      final now = DateTime.now();
                                      final picked = await showDatePicker(
                                        context: context,
                                        initialDate: _dueDate ?? now,
                                        firstDate: DateTime(now.year - 5),
                                        lastDate: DateTime(now.year + 5),
                                      );
                                      if (picked != null) setState(() => _dueDate = picked);
                                    }
                                  : null,
                            ),
                            if (_dueDate != null)
                              IconButton(
                                tooltip: 'Clear date',
                                icon: const Icon(Icons.clear),
                                onPressed: _canEdit() ? () => setState(() => _dueDate = null) : null,
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (!_canEdit())
                          const Text(
                            'You have READ-only access to this resource.',
                            style: TextStyle(color: Colors.grey),
                          ),
                      ],
                    ),
    );
  }

  // ---- TTL <-> Task helpers (PodService format) ----

  dynamic _extractJsonFromTtl(String ttl) {
    final tripleDq = RegExp(r'"""(.*?)"""', dotAll: true);
    for (final m in tripleDq.allMatches(ttl)) {
      final payload = m.group(1);
      if (payload != null) {
        try {
          return json.decode(payload.trim());
        } catch (_) {}
      }
    }

    int i = ttl.indexOf('{'), j = ttl.lastIndexOf('}');
    if (i != -1 && j > i) {
      try {
        return json.decode(ttl.substring(i, j + 1));
      } catch (_) {}
    }

    i = ttl.indexOf('[');
    j = ttl.lastIndexOf(']');
    if (i != -1 && j > i) {
      try {
        return json.decode(ttl.substring(i, j + 1));
      } catch (_) {}
    }

    return null;
  }

  String _taskToTurtle(Task t) {
    final jsonStr = json.encode(t.toJson());
    return '''@prefix : <#> .
@prefix solid: <http://www.w3.org/ns/solid/terms#> .
@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .

:task a solid:Resource ;
      solid:content """$jsonStr""" ;
      :lastUpdated "${DateTime.now().toIso8601String()}"^^xsd:dateTime .
''';
  }
}
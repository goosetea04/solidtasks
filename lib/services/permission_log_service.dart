import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:solidpod/solidpod.dart';
import '../utils/pod_utils.dart';

// Permission log literals for ACP-based sharing
enum PermissionLogLiteral {
  logtime('logtime'),
  resource('resource'),
  owner('owner'),
  granter('granter'),
  recipient('recipient'),
  type('type'),
  permissions('permissions'),
  acpPattern('acpPattern'),
  expiryDate('expiryDate');

  const PermissionLogLiteral(this._value);
  final String _value;
  String get label => _value;
}

// Service for managing permission logs in ACP environment
class PermissionLogService {
  // Create a permission log entry
  static List<String> createPermLogEntry({
    required List<String> permissionList,
    required String resourceUrl,
    required String ownerWebId,
    required String permissionType,
    required String granterWebId,
    required String recipientWebId,
    String? acpPattern,
    DateTime? expiryDate,
  }) {
    final permissionListStr = permissionList.join(',');
    final dateTimeStr = DateFormat('yyyyMMddTHHmmss').format(DateTime.now());
    final logEntryId = DateFormat('yyyyMMddTHHmmssSSS').format(DateTime.now());
    
    final parts = [
      dateTimeStr,
      resourceUrl,
      ownerWebId,
      permissionType,
      granterWebId,
      recipientWebId,
      permissionListStr.toLowerCase(),
      acpPattern ?? 'basic',
      expiryDate?.toIso8601String() ?? 'none',
    ];
    
    final logEntryStr = parts.join(';');
    return [logEntryId, logEntryStr];
  }

  /// Add a log entry to relevant log files (owner, granter, and recipient)
  /// Server is configured with public agent write access to logs
  static Future<void> logPermissionChange({
    required String resourceUrl,
    required String ownerWebId,
    required String granterWebId,
    required String recipientWebId,
    required List<String> permissionList,
    required String permissionType,
    String? acpPattern,
    DateTime? expiryDate,
  }) async {
    // 🔧 NORMALIZE all WebIDs before comparison
    final normalizedOwner = PodUtils.normalizeWebId(ownerWebId);
    final normalizedGranter = PodUtils.normalizeWebId(granterWebId);
    final normalizedRecipient = PodUtils.normalizeWebId(recipientWebId);

    debugPrint('🔍 Normalized WebIDs:');
    debugPrint('   Owner: $normalizedOwner');
    debugPrint('   Granter: $normalizedGranter');
    debugPrint('   Recipient: $normalizedRecipient');

    final logEntry = createPermLogEntry(
      permissionList: permissionList,
      resourceUrl: resourceUrl,
      ownerWebId: ownerWebId,
      permissionType: permissionType,
      granterWebId: granterWebId,
      recipientWebId: recipientWebId,
      acpPattern: acpPattern,
      expiryDate: expiryDate,
    );

    final logEntryId = logEntry[0];
    final logEntryStr = logEntry[1];

    // Track which logs succeeded/failed and which were skipped
    final results = <String, String>{};

    // Write to granter's log
    try {
      await _addLogEntry(granterWebId, logEntryId, logEntryStr);
      results['granter'] = 'success';
      debugPrint('✅ Logged to granter\'s POD: $granterWebId');
    } catch (e) {
      results['granter'] = 'failed: $e';
      debugPrint('❌ Failed to log to granter\'s POD: $e');
    }

    // Write to owner's log if different from granter
    if (normalizedOwner != normalizedGranter) {
      try {
        await _addLogEntry(ownerWebId, logEntryId, logEntryStr);
        results['owner'] = 'success';
        debugPrint('✅ Logged to owner\'s POD: $ownerWebId');
      } catch (e) {
        results['owner'] = 'failed: $e';
        debugPrint('❌ Failed to log to owner\'s POD: $e');
      }
    } else {
      results['owner'] = 'skipped (same as granter)';
      debugPrint('⏭️ Skipped owner log (same as granter)');
    }

    // Write to recipient's log (enabled via public agent access)
    if (normalizedRecipient != normalizedGranter && normalizedRecipient != normalizedOwner) {
      try {
        await _addLogEntry(recipientWebId, logEntryId, logEntryStr);
        results['recipient'] = 'success';
        debugPrint('✅ Logged to recipient\'s POD: $recipientWebId');
      } catch (e) {
        results['recipient'] = 'failed: $e';
        debugPrint('❌ Failed to log to recipient\'s POD: $e');
      }
    } else {
      results['recipient'] = 'skipped (duplicate)';
      debugPrint('⏭️ Skipped recipient log (duplicate)');
    }

    // Log summary
    final successCount = results.values.where((v) => v == 'success').length;
    final totalAttempts = results.values.where((v) => v != 'skipped (same as granter)' && v != 'skipped (duplicate)').length;
    debugPrint('📊 Permission log summary: $successCount/$totalAttempts logs written successfully');
    debugPrint('   Details: $results');
    
    if (successCount == 0 && totalAttempts > 0) {
      throw Exception('Failed to write to any permission logs');
    }
  }

  /// Add log entry to a specific user's log file
  static Future<void> _addLogEntry(
    String webId,
    String logEntryId,
    String logEntryStr,
  ) async {
    try {
      final logFileUrl = PodUtils.getPermissionLogUrl(webId);
      
      // Ensure log file exists
      await _ensureLogFileExists(logFileUrl, webId);

      // Use dynamic namespaces based on the user's WebID
      final logNamespace = PodUtils.getLogNamespace(webId);
      final dataNamespace = PodUtils.getDataNamespace(webId);

      // Create SPARQL update query with dynamic namespaces
      final insertQuery = '''
PREFIX log: <$logNamespace>
PREFIX data: <$dataNamespace>
INSERT DATA {
  log:$logEntryId data:log "$logEntryStr" .
}
''';

      await PodUtils.executeSparqlUpdate(logFileUrl, insertQuery);
      debugPrint('Log entry added to $webId');
    } catch (e) {
      debugPrint('Failed to add log entry for $webId: $e');
      rethrow; // Rethrow so calling code knows it failed
    }
  }

  /// Ensure log file and directory exist
  static Future<void> _ensureLogFileExists(String logFileUrl, String webId) async {
    try {
      final exists = await PodUtils.checkResourceExists(logFileUrl);

      if (!exists) {
        final dirUrl = PodUtils.getParentDirectory(logFileUrl);
        await PodUtils.ensureDirectoryExists(dirUrl);
        await _createLogFile(logFileUrl, webId);
      }
    } catch (e) {
      debugPrint('Error ensuring log file exists: $e');
      rethrow;
    }
  }

  /// Create initial log file with proper structure using dynamic namespaces
  static Future<void> _createLogFile(String logFileUrl, String webId) async {
    try {
      final logNamespace = PodUtils.getLogNamespace(webId);
      final dataNamespace = PodUtils.getDataNamespace(webId);
      
      final initialContent = '''@prefix log: <$logNamespace> .
@prefix data: <$dataNamespace> .
@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .

# Permission log file for $webId
# Created: ${DateTime.now().toIso8601String()}
''';

      final (:accessToken, :dPopToken) = await getTokensForResource(logFileUrl, 'PUT');
      
      final response = await http.put(
        Uri.parse(logFileUrl),
        headers: {
          'Content-Type': 'text/turtle',
          'Authorization': 'DPoP $accessToken',
          'DPoP': dPopToken,
        },
        body: initialContent,
      );

      if (![200, 201, 204].contains(response.statusCode)) {
        throw Exception('Failed to create log file: ${response.statusCode}');
      }
      
      debugPrint('Created log file: $logFileUrl');
      
      // Set ACR to allow public agent write access (for cross-pod logging)
      await _setLogFileAcr(logFileUrl, webId);
      
    } catch (e) {
      debugPrint('Error creating log file: $e');
      rethrow;
    }
  }

  /// Set ACR for log file to allow public agent write access
  static Future<void> _setLogFileAcr(String logFileUrl, String webId) async {
    try {
      final normalizedWebId = PodUtils.normalizeWebId(webId);
      final acrUrl = '$logFileUrl.acr';
      
      final acrBody = '''@prefix acp: <http://www.w3.org/ns/solid/acp#> .
@prefix acl: <http://www.w3.org/ns/auth/acl#> .

<> a acp:AccessControlResource ;
   acp:accessControl <#ownerAccess>, <#publicWriteAccess> .

<#ownerMatcher> a acp:Matcher ;
   acp:agent <$normalizedWebId> .

<#ownerAccess> a acp:AccessControl ;
   acp:apply <#ownerPolicy> .

<#ownerPolicy> a acp:Policy ;
   acp:allow acl:Read, acl:Write, acl:Control ;
   acp:anyOf <#ownerMatcher> .

<#publicMatcher> a acp:Matcher ;
   acp:agent acp:PublicAgent .

<#publicWriteAccess> a acp:AccessControl ;
   acp:apply <#publicPolicy> .

<#publicPolicy> a acp:Policy ;
   acp:allow acl:Write, acl:Append ;
   acp:anyOf <#publicMatcher> .
''';

      final (:accessToken, :dPopToken) = await getTokensForResource(acrUrl, 'PUT');
      
      final response = await http.put(
        Uri.parse(acrUrl),
        headers: {
          'Content-Type': 'text/turtle',
          'Authorization': 'DPoP $accessToken',
          'DPoP': dPopToken,
        },
        body: acrBody,
      );

      if (![200, 201, 204].contains(response.statusCode)) {
        throw Exception('Failed to set log file ACR: ${response.statusCode}');
      }
      
      debugPrint('Set ACR for log file with public write access');
      
    } catch (e) {
      debugPrint('Error setting log file ACR: $e');
      rethrow;
    }
  }

  /// Fetch user's permission logs
  static Future<List<PermissionLogEntry>> fetchUserLogs() async {
    try {
      final webId = await getWebId();
      if (webId == null) return [];

      final logFileUrl = PodUtils.getPermissionLogUrl(webId);
      final logContent = await PodUtils.readTurtleContent(logFileUrl);
      
      debugPrint('Fetched log content: $logContent');
      if (logContent == null) return [];

      return _parseLogEntries(logContent, webId);
    } catch (e) {
      debugPrint('Error fetching user logs: $e');
      return [];
    }
  }

  // Parse log entries from Turtle content using dynamic namespaces
  static List<PermissionLogEntry> _parseLogEntries(String turtleContent, String webId) {
    final entries = <PermissionLogEntry>[];
    
    debugPrint('🔍 Parsing log entries...');
    debugPrint('   Content length: ${turtleContent.length} chars');
    
    // Try line-by-line parsing first (more reliable)
    final lines = turtleContent.split('\n');
    int linesParsed = 0;
    
    for (var line in lines) {
      // Look for lines containing log entries
      if (line.contains('log#') && line.contains('data#log') && line.contains('"')) {
        linesParsed++;
        debugPrint('   📄 Processing line: ${line.substring(0, line.length > 80 ? 80 : line.length)}...');
        
        // Extract log ID
        final logIdMatch = RegExp(r'log#(\d+)').firstMatch(line);
        if (logIdMatch == null) {
          debugPrint('      ⚠️ No log ID found');
          continue;
        }
        final logId = logIdMatch.group(1)!;
        
        // Extract data string between quotes
        final dataMatch = RegExp(r'"([^"]+)"').firstMatch(line);
        if (dataMatch == null) {
          debugPrint('      ⚠️ No quoted data found');
          continue;
        }
        final logData = dataMatch.group(1)!;
        
        debugPrint('      ✓ Extracted - ID: $logId, Data length: ${logData.length}');
        
        final entry = _parseLogData(logId, logData);
        if (entry != null) {
          entries.add(entry);
          debugPrint('      ✅ Successfully parsed entry for: ${entry.resourceUrl.split('/').last}');
        } else {
          debugPrint('      ❌ Failed to parse entry data');
        }
      }
    }

    debugPrint('   Processed $linesParsed lines with log entries');
    entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    debugPrint('📊 Total entries parsed: ${entries.length}');
    
    return entries;
  }

  // Parse individual log data string
  static PermissionLogEntry? _parseLogData(String logId, String logData) {
    try {
      final parts = logData.split(';');
      if (parts.length < 7) {
        debugPrint('⚠️ Log data has insufficient parts: ${parts.length}');
        return null;
      }

      // Parse timestamp in format: yyyyMMddTHHmmss
      DateTime? timestamp;
      try {
        final timestampStr = parts[0];
        // Convert 20251026T102958 to 2025-10-26T10:29:58
        if (timestampStr.length >= 15) {
          final year = timestampStr.substring(0, 4);
          final month = timestampStr.substring(4, 6);
          final day = timestampStr.substring(6, 8);
          final hour = timestampStr.substring(9, 11);
          final minute = timestampStr.substring(11, 13);
          final second = timestampStr.substring(13, 15);
          final isoFormat = '$year-$month-${day}T$hour:$minute:$second';
          timestamp = DateTime.parse(isoFormat);
        } else {
          debugPrint('⚠️ Invalid timestamp format: $timestampStr');
          timestamp = DateTime.now(); // Fallback
        }
      } catch (e) {
        debugPrint('⚠️ Error parsing timestamp: $e');
        timestamp = DateTime.now(); // Fallback
      }

      return PermissionLogEntry(
        id: logId,
        timestamp: timestamp,
        resourceUrl: parts[1],
        ownerWebId: parts[2],
        permissionType: parts[3],
        granterWebId: parts[4],
        recipientWebId: parts[5],
        permissions: parts[6].split(','),
        acpPattern: parts.length > 7 ? parts[7] : 'basic',
        expiryDate: parts.length > 8 && parts[8] != 'none' 
            ? DateTime.tryParse(parts[8]) 
            : null,
      );
    } catch (e) {
      debugPrint('❌ Error parsing log entry: $e');
      debugPrint('   Log data: $logData');
      return null;
    }
  }

  static Map<String, PermissionLogEntry> getLatestLogs(
    List<PermissionLogEntry> entries,
  ) {
    final latestMap = <String, PermissionLogEntry>{};
    
    for (final entry in entries) {
      final existing = latestMap[entry.resourceUrl];
      if (existing == null || entry.timestamp.isAfter(existing.timestamp)) {
        latestMap[entry.resourceUrl] = entry;
      }
    }
    
    return latestMap;
  }

  static List<PermissionLogEntry> filterByFilename(
    List<PermissionLogEntry> entries,
    String filename,
  ) {
    return entries.where((e) => e.resourceUrl.contains(filename)).toList();
  }

  static List<PermissionLogEntry> filterByOwner(
    List<PermissionLogEntry> entries,
    String ownerWebId,
  ) {
    return entries.where((e) => e.ownerWebId == ownerWebId).toList();
  }

  static Future<List<PermissionLogEntry>> getSharedWithMe() async {
    final logs = await fetchUserLogs();
    final webId = await getWebId();
    if (webId == null) return [];

    return logs
        .where((log) => 
            log.recipientWebId == webId && 
            log.permissionType == 'grant')
        .toList();
  }

  static Future<List<PermissionLogEntry>> getSharedByMe() async {
    final logs = await fetchUserLogs();
    final webId = await getWebId();
    if (webId == null) return [];

    return logs
        .where((log) => 
            log.granterWebId == webId && 
            log.permissionType == 'grant')
        .toList();
  }
}

/// Data model for permission log entry
class PermissionLogEntry {
  final String id;
  final DateTime timestamp;
  final String resourceUrl;
  final String ownerWebId;
  final String permissionType;
  final String granterWebId;
  final String recipientWebId;
  final List<String> permissions;
  final String acpPattern;
  final DateTime? expiryDate;

  PermissionLogEntry({
    required this.id,
    required this.timestamp,
    required this.resourceUrl,
    required this.ownerWebId,
    required this.permissionType,
    required this.granterWebId,
    required this.recipientWebId,
    required this.permissions,
    required this.acpPattern,
    this.expiryDate,
  });

  bool get isExpired => expiryDate != null && DateTime.now().isAfter(expiryDate!);
  bool get isGrant => permissionType == 'grant';
  bool get isRevoke => permissionType == 'revoke';

  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': timestamp.toIso8601String(),
    'resourceUrl': resourceUrl,
    'ownerWebId': ownerWebId,
    'permissionType': permissionType,
    'granterWebId': granterWebId,
    'recipientWebId': recipientWebId,
    'permissions': permissions,
    'acpPattern': acpPattern,
    'expiryDate': expiryDate?.toIso8601String(),
  };
}
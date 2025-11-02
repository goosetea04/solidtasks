import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:solidpod/solidpod.dart';
import 'pod_service_acp.dart';
import 'auth_service.dart';
import 'permission_log_service.dart';
import '../utils/pod_utils.dart';

class SharingService {
  static Future<void> shareResourceWithUser({
    required String resourceUrl,
    required String ownerWebId,
    required String recipientWebId,
    required String shareType, // 'read', 'write', 'control', 'append'
    String? message,
    String? acpPattern = 'basic',
    Map<String, dynamic>? acpOptions,
  }) async {
    try {
      debugPrint('📄 Starting share process...');
      debugPrint('   Resource: $resourceUrl');
      debugPrint('   Owner: $ownerWebId');
      debugPrint('   Recipient: $recipientWebId');
      
      // 🔧 Normalize the recipient WebID before storing in log
      final normalizedRecipient = PodUtils.normalizeWebId(recipientWebId);
      debugPrint('   Normalized recipient: $normalizedRecipient');
      
      // Apply ACP policy based on pattern
      await _applyAcpPattern(
        resourceUrl, 
        ownerWebId, 
        normalizedRecipient,  // Use normalized version
        shareType, 
        acpPattern, 
        acpOptions,
      );
      
      // Permission logging is handled automatically by AcpService methods
      // (applyOwnerOnly, applySharedRead, applySharedWrite, etc. all log internally)
      
      // Send sharing notification to recipient
      await _sendSharingNotification(
        ownerWebId: ownerWebId,
        recipientWebId: normalizedRecipient,  // Use normalized version
        resourceUrl: resourceUrl,
        shareType: shareType,
        message: message,
      );
      
      // Log the share in owner's outgoing shares
      await _logOutgoingShare(ownerWebId, resourceUrl, normalizedRecipient, shareType);
      
      debugPrint('Successfully shared $resourceUrl with $normalizedRecipient');
    } catch (e) {
      debugPrint('Error sharing resource: $e');
      rethrow;
    }
  }
  
  static Future<void> _applyAcpPattern(
    String resourceUrl,
    String ownerWebId,
    String recipientWebId,
    String shareType,
    String? pattern,
    Map<String, dynamic>? options,
  ) async {
    switch (pattern) {
      case 'app_scoped':
        await AcpService.applySharedRead(
          resourceUrl,
          ownerWebId,
          shareType == 'read' ? [recipientWebId] : [],
        );
        break;
      
      case 'delegated_sharing':
        await AcpService.applySharedWrite(
          resourceUrl,
          ownerWebId,
          [recipientWebId],
        );
        break;
      
      case 'role_based':
        await AcpService.applyTeamCollab(
          resourceUrl,
          ownerWebId,
          adminWebIds: shareType == 'control' ? [recipientWebId] : null,
          viewerWebIds: shareType == 'read' ? [recipientWebId] : null,
          editorWebIds: shareType == 'write' ? [recipientWebId] : null,
        );
        break;
      
      default: // Basic sharing
        final readWebIds = ['read', 'write', 'control'].contains(shareType) ? [recipientWebId] : null;
        final writeWebIds = ['write', 'control'].contains(shareType) ? [recipientWebId] : null;
        final controlWebIds = shareType == 'control' ? [recipientWebId] : null;
        
        if (writeWebIds != null && writeWebIds.isNotEmpty) {
          await AcpService.applySharedWrite(resourceUrl, ownerWebId, writeWebIds);
        } else if (readWebIds != null && readWebIds.isNotEmpty) {
          await AcpService.applySharedRead(resourceUrl, ownerWebId, readWebIds);
        } else {
          await AcpService.applyOwnerOnly(resourceUrl, ownerWebId);
        }
    }
  }
  

  /// Send notification to recipient's inbox
  static Future<void> _sendSharingNotification({
    required String ownerWebId,
    required String recipientWebId,
    required String resourceUrl,
    required String shareType,
    String? message,
  }) async {
    try {
      debugPrint('📬 Attempting to send notification...');
      debugPrint('   Recipient: $recipientWebId');
      
      final inboxUrl = await _discoverInboxUrl(recipientWebId);
      debugPrint('   Inbox URL: ${inboxUrl ?? "NOT FOUND"}');
      
      if (inboxUrl == null) {
        debugPrint('warning Could not find inbox for $recipientWebId');
        // Don't throw - inbox is optional
        return;
      }

      final notification = _createSharingNotification(
        ownerWebId: ownerWebId,
        recipientWebId: recipientWebId,
        resourceUrl: resourceUrl,
        shareType: shareType,
        message: message,
      );

      debugPrint('   Posting notification to inbox...');
      await _postToInbox(inboxUrl, notification);
      debugPrint('(check) Notification sent successfully');
      
    } catch (e) {
      debugPrint('warning Error sending sharing notification: $e');
      // Don't rethrow - notification is optional
    }
  }

  /// Discover inbox URL from WebID profile
  static Future<String?> _discoverInboxUrl(String webId) async {
    try {
      final profileUrl = webId.contains('#') ? webId.split('#')[0] : webId;
      final content = await PodUtils.readTurtleContent(profileUrl);
      
      if (content == null) return null;

      // Simple pattern matching for inbox
      final inboxPattern = RegExp(r'<([^>]+)>\s+a\s+<http://www\.w3\.org/ns/ldp#inbox>');
      final match = inboxPattern.firstMatch(content);
      
      if (match != null) {
        return match.group(1);
      }

      // Alternative: look for ldp:inbox predicate
      final inboxPredPattern = RegExp(r'ldp:inbox\s+<([^>]+)>');
      final predMatch = inboxPredPattern.firstMatch(content);
      return predMatch?.group(1);
      
    } catch (e) {
      debugPrint('Error discovering inbox: $e');
      return null;
    }
  }

  /// Create RDF notification for sharing
  static String _createSharingNotification({
    required String ownerWebId,
    required String recipientWebId,
    required String resourceUrl,
    required String shareType,
    String? message,
  }) {
    final timestamp = DateTime.now().toIso8601String();
    final notificationId = '#notification-${DateTime.now().millisecondsSinceEpoch}';
    
    return '''@prefix as: <https://www.w3.org/ns/activitystreams#> .
@prefix acl: <http://www.w3.org/ns/auth/acl#> .
@prefix dc: <http://purl.org/dc/terms/> .
@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .

<$notificationId> a as:Announce ;
  as:actor <$ownerWebId> ;
  as:target <$recipientWebId> ;
  as:object <$resourceUrl> ;
  as:summary "${message ?? 'Resource shared with you'}" ;
  dc:created "${timestamp}"^^xsd:dateTime ;
  acl:mode acl:${shareType[0].toUpperCase()}${shareType.substring(1)} .
''';
  }

  /// Post notification to inbox
  static Future<void> _postToInbox(String inboxUrl, String notification) async {
    final (:accessToken, :dPopToken) = await getTokensForResource(inboxUrl, 'POST');
    
    final response = await http.post(
      Uri.parse(inboxUrl),
      headers: {
        'Content-Type': 'text/turtle',
        'Authorization': 'DPoP $accessToken',
        'DPoP': dPopToken,
      },
      body: notification,
    );

    if (![200, 201, 204].contains(response.statusCode)) {
      throw Exception('Failed to post to inbox: ${response.statusCode}');
    }
  }

  /// Log outgoing share for owner's reference
  static Future<void> _logOutgoingShare(
    String ownerWebId,
    String resourceUrl,
    String recipientWebId,
    String shareType,
  ) async {
    try {
      final outboxUrl = await _getOutboxUrl(ownerWebId);
      if (outboxUrl != null) {
        final shareLog = _createShareLog(ownerWebId, resourceUrl, recipientWebId, shareType);
        await _postToInbox(outboxUrl, shareLog);
      }
    } catch (e) {
      debugPrint('Error logging outgoing share: $e');
    }
  }

  static String _createShareLog(String ownerWebId, String resourceUrl, String recipientWebId, String shareType) {
    final timestamp = DateTime.now().toIso8601String();
    return '''@prefix as: <https://www.w3.org/ns/activitystreams#> .
@prefix dc: <http://purl.org/dc/terms/> .
@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .

<#share-${DateTime.now().millisecondsSinceEpoch}> a as:Offer ;
  as:actor <$ownerWebId> ;
  as:target <$recipientWebId> ;
  as:object <$resourceUrl> ;
  as:summary "Shared resource: $shareType access" ;
  dc:created "${timestamp}"^^xsd:dateTime .
''';
  }

  static Future<String?> _getOutboxUrl(String webId) async {
    return null; // Placeholder
  }

  /// Get shared resources for a user from permission logs
  static Future<List<SharedResource>> getSharedResources(String userWebId) async {
    try {
      debugPrint('(searching) Getting shared resources for: $userWebId');
      
      // Normalize the user's WebID
      final normalizedUserWebId = PodUtils.normalizeWebId(userWebId);
      debugPrint('   Normalized: $normalizedUserWebId');
      
      // Get permission logs instead of inbox
      final logs = await PermissionLogService.fetchUserLogs();
      debugPrint('   Found ${logs.length} total logs');
      
      // Filter for grants where user is recipient
      final relevantLogs = logs.where((log) =>
        PodUtils.normalizeWebId(log.recipientWebId) == normalizedUserWebId &&
        log.permissionType == 'grant'
      ).toList();
      
      debugPrint('   Found ${relevantLogs.length} relevant shares');
      
      // Convert to SharedResource objects
      return relevantLogs.map((log) => SharedResource(
        id: log.id,
        resourceUrl: log.resourceUrl,
        sharedBy: log.granterWebId,
        sharedWith: log.recipientWebId,
        shareType: log.permissions.join(','),
        timestamp: log.timestamp,
        message: null,
      )).toList();
      
    } catch (e) {
      debugPrint('(fail) Error getting shared resources: $e');
      return [];
    }
  }

  /// Test if user has access to a resource
  static Future<bool> canAccessResource(String resourceUrl, String userWebId) async {
    try {
      debugPrint('(searching) Testing access to: $resourceUrl');
      final (:accessToken, :dPopToken) = await getTokensForResource(resourceUrl, 'GET');
      final response = await http.head(
        Uri.parse(resourceUrl),
        headers: {
          'Authorization': 'DPoP $accessToken',
          'DPoP': dPopToken,
        },
      );
      
      final canAccess = [200, 204].contains(response.statusCode);
      debugPrint('   Access result: ${canAccess ? "(check) GRANTED" : "(fail) DENIED"} (${response.statusCode})');
      return canAccess;
    } catch (e) {
      debugPrint('(fail) Error testing resource access: $e');
      return false;
    }
  }
}

/// Data model for shared resources
class SharedResource {
  final String id;
  final String resourceUrl;
  final String sharedBy;
  final String sharedWith;
  final String shareType;
  final DateTime timestamp;
  final String? message;

  SharedResource({
    required this.id,
    required this.resourceUrl,
    required this.sharedBy,
    required this.sharedWith,
    required this.shareType,
    required this.timestamp,
    this.message,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'resourceUrl': resourceUrl,
    'sharedBy': sharedBy,
    'sharedWith': sharedWith,
    'shareType': shareType,
    'timestamp': timestamp.toIso8601String(),
    'message': message,
  };
}
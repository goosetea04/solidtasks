import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:solidpod/solidpod.dart';
import 'pod_service_acp.dart';
import 'auth_service.dart';
import 'permission_log_service.dart';

class SharingService {
  /// Share a resource with another user by creating both ACP and notification
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
      // Apply ACP policy based on pattern
      await _applyAcpPattern(
        resourceUrl, 
        ownerWebId, 
        recipientWebId, 
        shareType, 
        acpPattern, 
        acpOptions,
      );
      
      // Log the permission change
      final currentUserWebId = await AuthService.getCurrentUserWebId();
      await PermissionLogService.logPermissionChange(
        resourceUrl: resourceUrl,
        ownerWebId: ownerWebId,
        granterWebId: currentUserWebId ?? ownerWebId,
        recipientWebId: recipientWebId,
        permissionList: [shareType],
        permissionType: 'grant',
        acpPattern: acpPattern,
        expiryDate: acpOptions?['validUntil'],
      );
      
      // Send sharing notification to recipient
      await _sendSharingNotification(
        ownerWebId: ownerWebId,
        recipientWebId: recipientWebId,
        resourceUrl: resourceUrl,
        shareType: shareType,
        message: message,
      );
      
      // Log the share in owner's outgoing shares
      await _logOutgoingShare(ownerWebId, resourceUrl, recipientWebId, shareType);
      
      debugPrint('Successfully shared $resourceUrl with $recipientWebId');
    } catch (e) {
      debugPrint('Error sharing resource: $e');
      rethrow;
    }
  }

  /// Apply ACP pattern based on sharing requirements
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
        await AcpService.writeAppScopedAcr(
          resourceUrl,
          ownerWebId,
          allowReadWebIds: shareType == 'read' ? [recipientWebId] : null,
          allowedClientId: options?['clientId'] ?? AcpService.officialClientId,
        );
        break;
      
      case 'time_limited':
        await AcpService.writeTimeLimitedAcr(
          resourceUrl,
          ownerWebId,
          tempAccessWebIds: [recipientWebId],
          validUntil: options?['validUntil'] ?? DateTime.now().add(const Duration(days: 7)),
        );
        break;
      
      case 'delegated_sharing':
        await AcpService.writeDelegatedSharingAcr(
          resourceUrl,
          ownerWebId,
          recipientWebId, // recipient acts as manager
          contractorWebIds: options?['contractors'],
        );
        break;
      
      case 'role_based':
        await AcpService.writeRoleBasedAcr(
          resourceUrl,
          ownerWebId,
          adminRoles: shareType == 'control' ? [recipientWebId] : null,
          reviewerRoles: shareType == 'read' ? [recipientWebId] : null,
          contributorRoles: shareType == 'write' ? [recipientWebId] : null,
        );
        break;
      
      default: // Basic sharing
        final readWebIds = ['read', 'write', 'control'].contains(shareType) ? [recipientWebId] : null;
        final writeWebIds = ['write', 'control'].contains(shareType) ? [recipientWebId] : null;
        final controlWebIds = shareType == 'control' ? [recipientWebId] : null;
        
        await AcpPresets.writeAcrForResource(
          resourceUrl,
          ownerWebId,
          allowReadWebIds: readWebIds,
          allowWriteWebIds: writeWebIds,
          allowControlWebIds: controlWebIds,
        );
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
      debugPrint('🔔 Attempting to send notification...');
      debugPrint('   Recipient: $recipientWebId');
      
      final inboxUrl = await _discoverInboxUrl(recipientWebId);
      debugPrint('   Inbox URL: ${inboxUrl ?? "NOT FOUND"}');
      
      if (inboxUrl == null) {
        debugPrint('❌ Could not find inbox for $recipientWebId');
        // DON'T RETURN - throw instead so we know it failed
        throw Exception('Inbox not found for $recipientWebId');
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
      debugPrint('✅ Notification sent successfully');
      
    } catch (e) {
      debugPrint('❌ Error sending sharing notification: $e');
      rethrow; // Let caller know it failed
    }
  }

  /// Discover inbox URL from WebID profile
  static Future<String?> _discoverInboxUrl(String webId) async {
    try {
      final profileUrl = webId.contains('#') ? webId.split('#')[0] : webId;
      final (:accessToken, :dPopToken) = await getTokensForResource(profileUrl, 'GET');
      
      final response = await http.get(
        Uri.parse(profileUrl),
        headers: {
          'Accept': 'text/turtle, application/ld+json',
          'Authorization': 'DPoP $accessToken',
          'DPoP': dPopToken,
        },
      );

      if (response.statusCode != 200) return null;

      // Simple pattern matching for inbox
      final content = response.body;
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

  /// Get shared resources for a user
  static Future<List<SharedResource>> getSharedResources(String userWebId) async {
    try {
      final inboxUrl = await _discoverInboxUrl(userWebId);
      if (inboxUrl == null) return [];

      final (:accessToken, :dPopToken) = await getTokensForResource(inboxUrl, 'GET');
      final response = await http.get(
        Uri.parse(inboxUrl),
        headers: {
          'Accept': 'text/turtle, application/ld+json',
          'Authorization': 'DPoP $accessToken',
          'DPoP': dPopToken,
        },
      );

      if (response.statusCode != 200) return [];

      return _parseSharedResources(response.body, userWebId);
    } catch (e) {
      debugPrint('Error getting shared resources: $e');
      return [];
    }
  }

  /// Parse shared resources from inbox
  static List<SharedResource> _parseSharedResources(String inboxContent, String userWebId) {
    final resources = <SharedResource>[];
    
    final sharePattern = RegExp(
      r'<([^>]+)>\s+a\s+as:Announce\s*;.*?as:object\s+<([^>]+)>.*?as:actor\s+<([^>]+)>',
      multiLine: true,
      dotAll: true,
    );

    final matches = sharePattern.allMatches(inboxContent);
    for (final match in matches) {
      final notificationId = match.group(1);
      final resourceUrl = match.group(2);
      final actorWebId = match.group(3);
      
      if (notificationId != null && resourceUrl != null && actorWebId != null) {
        resources.add(SharedResource(
          id: notificationId,
          resourceUrl: resourceUrl,
          sharedBy: actorWebId,
          sharedWith: userWebId,
          shareType: 'read',
          timestamp: DateTime.now(),
        ));
      }
    }
    
    return resources;
  }

  /// Test if user has access to a resource
  static Future<bool> canAccessResource(String resourceUrl, String userWebId) async {
    try {
      final (:accessToken, :dPopToken) = await getTokensForResource(resourceUrl, 'GET');
      final response = await http.head(
        Uri.parse(resourceUrl),
        headers: {
          'Authorization': 'DPoP $accessToken',
          'DPoP': dPopToken,
        },
      );
      
      return [200, 204].contains(response.statusCode);
    } catch (e) {
      debugPrint('Error testing resource access: $e');
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
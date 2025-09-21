import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:solidpod/solidpod.dart';

class AcpService {
  /// Fetch the .acr body for a resource (returns null if not found / error).
  static Future<String?> fetchAcr(String resourceUrl) async {
    try {
      final acrUrl = '$resourceUrl.acr';
      final (:accessToken, :dPopToken) = await getTokensForResource(acrUrl, 'GET');
      final res = await http.get(
        Uri.parse(acrUrl),
        headers: {
          'Accept': 'text/turtle',
          'Authorization': 'DPoP $accessToken',
          'DPoP': dPopToken,
        },
      );
      if (res.statusCode == 200) return res.body;
      debugPrint('fetchAcr: non-200 for $acrUrl => ${res.statusCode}');
      return null;
    } catch (e) {
      debugPrint('Error fetching ACR: $e');
      return null;
    }
  }

  /// Write ACR for a resource (throws on failure).
  static Future<void> writeAcrForResource(
    String resourceUrl,
    String ownerWebId, {
    List<String>? allowReadWebIds,
    List<String>? allowWriteWebIds,
    List<String>? allowControlWebIds,
    bool publicRead = false,
  }) async {
    try {
      final acrUrl = '$resourceUrl.acr';
      final acrBody = _generateAcr(
        ownerWebId,
        allowReadWebIds: allowReadWebIds,
        allowWriteWebIds: allowWriteWebIds,
        allowControlWebIds: allowControlWebIds,
        publicRead: publicRead,
      );

      final (:accessToken, :dPopToken) = await getTokensForResource(acrUrl, 'PUT');
      final res = await http.put(
        Uri.parse(acrUrl),
        headers: {
          'Content-Type': 'text/turtle',
          'Authorization': 'DPoP $accessToken',
          'DPoP': dPopToken,
        },
        body: acrBody,
      );

      if (![200, 201, 204, 205].contains(res.statusCode)) {
        debugPrint('Failed to write ACR for $resourceUrl => ${res.statusCode} ${res.body}');
        throw Exception('Failed to write ACR: ${res.statusCode}');
      }

      debugPrint('ACR created/updated for $resourceUrl');
    } catch (e) {
      debugPrint('Error writing ACR for $resourceUrl: $e');
      rethrow;
    }
  }

  /// Convenience if you want a task-specific helper name (optional).
  static Future<String?> fetchAcrForTask(String taskFileUrl) => fetchAcr(taskFileUrl);
}

/// Improved ACP body generation with better structure
String _generateAcr(
  String ownerWebId, {
  List<String>? allowReadWebIds,
  List<String>? allowWriteWebIds,
  List<String>? allowControlWebIds,
  bool publicRead = false,
}) {
  final readList = allowReadWebIds ?? [];
  final writeList = allowWriteWebIds ?? [];
  final controlList = allowControlWebIds ?? [];

  // Build the list of allowed permissions
  final permissions = <String>[];
  if (readList.isNotEmpty || writeList.isNotEmpty || controlList.isNotEmpty || publicRead) {
    permissions.add('acl:Read');
  }
  if (writeList.isNotEmpty || controlList.isNotEmpty) {
    permissions.add('acl:Write');
  }
  if (controlList.isNotEmpty) {
    permissions.add('acl:Control');
  }

  // Build the list of agents
  final agents = <String>[];
  agents.addAll(readList.map((id) => '<$id>'));
  agents.addAll(writeList.map((id) => '<$id>'));
  agents.addAll(controlList.map((id) => '<$id>'));
  
  if (publicRead) {
    agents.add('<http://www.w3.org/ns/solid/acp#PublicAgent>');
  }

  // Remove duplicates
  final uniqueAgents = agents.toSet().toList();

  // Ensure owner WebID has proper format
  final ownerAgent = ownerWebId.endsWith('/profile/card#me') 
      ? '<$ownerWebId>' 
      : '<$ownerWebId/profile/card#me>';

  return '''@prefix acp: <http://www.w3.org/ns/solid/acp#> .
@prefix acl: <http://www.w3.org/ns/auth/acl#> .

<> a acp:AccessControlResource ;
   acp:accessControl <#ownerAccess>${uniqueAgents.isNotEmpty ? ', <#sharedAccess>' : ''} .

<#ownerAccess> a acp:AccessControl ;
   acp:apply <#ownerPolicy> .

<#ownerPolicy> a acp:Policy ;
   acp:allow acl:Read, acl:Write, acl:Control ;
   acp:anyOf ( $ownerAgent ) .

${uniqueAgents.isNotEmpty ? '''<#sharedAccess> a acp:AccessControl ;
   acp:apply <#sharedPolicy> .

<#sharedPolicy> a acp:Policy ;
   acp:allow ${permissions.join(', ')} ;
   acp:anyOf ( ${uniqueAgents.join(' ')} ) .''' : ''}
''';
}

/// Pre-baked presets for convenience
class AclPresets {
  static String ownerOnly(String ownerWebId) => _generateAcr(ownerWebId);
  
  static String ownerPlusRead(String ownerWebId, String collaboratorWebId) =>
      _generateAcr(ownerWebId, allowReadWebIds: [collaboratorWebId]);
  
  static String ownerPlusWrite(String ownerWebId, String collaboratorWebId) =>
      _generateAcr(
        ownerWebId, 
        allowReadWebIds: [collaboratorWebId], 
        allowWriteWebIds: [collaboratorWebId]
      );
  
  static String publicRead(String ownerWebId) => 
      _generateAcr(ownerWebId, publicRead: true);
  
  static String teamAccess(String ownerWebId, List<String> teamWebIds) =>
      _generateAcr(
        ownerWebId, 
        allowReadWebIds: teamWebIds, 
        allowWriteWebIds: teamWebIds
      );
}
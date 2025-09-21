import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:solidpod/solidpod.dart';

class AcpService {

  static const String officialClientId = 'https://clients.example.org/solidtasks-web#client';
  
  /// USE CASE 1: App-scoped access - Only official client can write
  static Future<void> writeAppScopedAcr(
    String resourceUrl,
    String ownerWebId, {
    List<String>? allowReadWebIds,
    String? allowedClientId,
  }) async {
    try {
      final acrUrl = '$resourceUrl.acr';
      final acrBody = _generateAppScopedAcr(
        ownerWebId,
        allowReadWebIds: allowReadWebIds,
        allowedClientId: allowedClientId ?? officialClientId,
      );

      await _writeAcr(acrUrl, acrBody);
    } catch (e) {
      debugPrint('Error writing app-scoped ACR: $e');
      rethrow;
    }
  }

  /// USE CASE 2: Delegated sharing - Manager can grant limited access
  static Future<void> writeDelegatedSharingAcr(
    String resourceUrl,
    String ownerWebId,
    String managerWebId, {
    List<String>? contractorWebIds,
    String? createdBy,
  }) async {
    try {
      final acrUrl = '$resourceUrl.acr';
      final acrBody = _generateDelegatedSharingAcr(
        ownerWebId,
        managerWebId,
        contractorWebIds: contractorWebIds,
        createdBy: createdBy,
      );

      await _writeAcr(acrUrl, acrBody);
    } catch (e) {
      debugPrint('Error writing delegated sharing ACR: $e');
      rethrow;
    }
  }

  /// USE CASE 3: Time-limited access
  static Future<void> writeTimeLimitedAcr(
    String resourceUrl,
    String ownerWebId, {
    List<String>? tempAccessWebIds,
    DateTime? validUntil,
  }) async {
    try {
      final acrUrl = '$resourceUrl.acr';
      final acrBody = _generateTimeLimitedAcr(
        ownerWebId,
        tempAccessWebIds: tempAccessWebIds,
        validUntil: validUntil,
      );

      await _writeAcr(acrUrl, acrBody);
    } catch (e) {
      debugPrint('Error writing time-limited ACR: $e');
      rethrow;
    }
  }

  /// USE CASE 4: Role-based access
  static Future<void> writeRoleBasedAcr(
    String resourceUrl,
    String ownerWebId, {
    List<String>? adminRoles,
    List<String>? reviewerRoles,
    List<String>? contributorRoles,
    String? resourceAuthor,
  }) async {
    try {
      final acrUrl = '$resourceUrl.acr';
      final acrBody = _generateRoleBasedAcr(
        ownerWebId,
        adminRoles: adminRoles,
        reviewerRoles: reviewerRoles,
        contributorRoles: contributorRoles,
        resourceAuthor: resourceAuthor,
      );

      await _writeAcr(acrUrl, acrBody);
    } catch (e) {
      debugPrint('Error writing role-based ACR: $e');
      rethrow;
    }
  }

  // ACR Generators for each use case

  static String _generateAppScopedAcr(
    String ownerWebId, {
    List<String>? allowReadWebIds,
    required String allowedClientId,
  }) {
    final readMatchers = (allowReadWebIds ?? []).map((id) => '<$id>').join(' ');
    
    return '''
@prefix acp: <http://www.w3.org/ns/solid/acp#>.
@prefix acl: <http://www.w3.org/ns/auth/acl#>.

<> a acp:AccessControlResource;
   acp:accessControl <#owner>, <#appWrite>, <#readers>.

<#owner> a acp:AccessControl; 
   acp:apply <#ownerPolicy>.

<#ownerPolicy> a acp:Policy; 
   acp:allow acl:Read, acl:Write, acl:Control;
   acp:anyOf ( <$ownerWebId/profile/card#me> ).

<#appWrite> a acp:AccessControl; 
   acp:apply <#clientPolicy>.

<#clientPolicy> a acp:Policy; 
   acp:allow acl:Write;
   acp:anyOf ( <$allowedClientId> ).

<#readers> a acp:AccessControl; 
   acp:apply <#readerPolicy>.

<#readerPolicy> a acp:Policy; 
   acp:allow acl:Read;
   acp:anyOf ( <$ownerWebId/profile/card#me> $readMatchers ).
''';
  }

  static String _generateDelegatedSharingAcr(
    String ownerWebId,
    String managerWebId, {
    List<String>? contractorWebIds,
    String? createdBy,
  }) {
    final contractorMatchers = (contractorWebIds ?? []).map((id) => '<$id>').join(' ');
    final timestamp = DateTime.now().toIso8601String();
    final creator = createdBy ?? ownerWebId;
    
    return '''
@prefix acp: <http://www.w3.org/ns/solid/acp#>.
@prefix acl: <http://www.w3.org/ns/auth/acl#>.
@prefix dct: <http://purl.org/dc/terms#>.
@prefix xsd: <http://www.w3.org/2001/XMLSchema#>.

<> a acp:AccessControlResource; 
   acp:accessControl <#owner>, <#manager>, <#contractors>.

<#owner> a acp:AccessControl; 
   acp:apply <#ownerPolicy>.

<#ownerPolicy> a acp:Policy; 
   acp:allow acl:Read, acl:Write, acl:Control;
   acp:anyOf ( <$ownerWebId/profile/card#me> );
   dct:creator <$creator/profile/card#me>; 
   dct:created "${timestamp}"^^xsd:dateTime.

<#manager> a acp:AccessControl; 
   acp:apply <#managerPolicy>.

<#managerPolicy> a acp:Policy; 
   acp:allow acl:Write;
   acp:anyOf ( <$managerWebId/profile/card#me> );
   dct:creator <$creator/profile/card#me>; 
   dct:created "${timestamp}"^^xsd:dateTime.

<#contractors> a acp:AccessControl; 
   acp:apply <#contractorPolicy>.

<#contractorPolicy> a acp:Policy; 
   acp:allow acl:Read;
   acp:anyOf ( $contractorMatchers );
   dct:creator <$managerWebId/profile/card#me>; 
   dct:created "${timestamp}"^^xsd:dateTime.
''';
  }

  static String _generateTimeLimitedAcr(
    String ownerWebId, {
    List<String>? tempAccessWebIds,
    DateTime? validUntil,
  }) {
    final tempMatchers = (tempAccessWebIds ?? []).map((id) => '<$id>').join(' ');
    final expiryDate = validUntil?.toIso8601String() ?? 
        DateTime.now().add(const Duration(days: 7)).toIso8601String();
    
    return '''
@prefix acp: <http://www.w3.org/ns/solid/acp#>.
@prefix acl: <http://www.w3.org/ns/auth/acl#>.
@prefix ex: <http://example.org/ns#>.
@prefix xsd: <http://www.w3.org/2001/XMLSchema#>.

<> a acp:AccessControlResource; 
   acp:accessControl <#owner>, <#guestTemp>.

<#owner> a acp:AccessControl; 
   acp:apply <#ownerPolicy>.

<#ownerPolicy> a acp:Policy; 
   acp:allow acl:Read, acl:Write, acl:Control;
   acp:anyOf ( <$ownerWebId/profile/card#me> ).

<#guestTemp> a acp:AccessControl; 
   acp:apply <#guestPolicy>.

<#guestPolicy> a acp:Policy; 
   acp:allow acl:Read;
   acp:anyOf ( $tempMatchers );
   ex:validUntil "${expiryDate}"^^xsd:dateTime.
''';
  }

  static String _generateRoleBasedAcr(
    String ownerWebId, {
    List<String>? adminRoles,
    List<String>? reviewerRoles,
    List<String>? contributorRoles,
    String? resourceAuthor,
  }) {
    final adminMatchers = (adminRoles ?? []).map((role) => '<$role>').join(' ');
    final reviewerMatchers = (reviewerRoles ?? []).map((role) => '<$role>').join(' ');
    final contributorMatchers = (contributorRoles ?? []).map((role) => '<$role>').join(' ');
    final timestamp = DateTime.now().toIso8601String();
    
    return '''
@prefix acp: <http://www.w3.org/ns/solid/acp#>.
@prefix acl: <http://www.w3.org/ns/auth/acl#>.
@prefix dct: <http://purl.org/dc/terms#>.
@prefix xsd: <http://www.w3.org/2001/XMLSchema#>.

<> a acp:AccessControlResource; 
   acp:accessControl <#admin>, <#reviewer>, <#author>.

<#admin> a acp:AccessControl; 
   acp:apply <#adminPolicy>.

<#adminPolicy> a acp:Policy; 
   acp:allow acl:Read, acl:Write, acl:Control;
   acp:anyOf ( $adminMatchers );
   dct:created "${timestamp}"^^xsd:dateTime.

<#reviewer> a acp:AccessControl; 
   acp:apply <#reviewerPolicy>.

<#reviewerPolicy> a acp:Policy; 
   acp:allow acl:Read;
   acp:anyOf ( $reviewerMatchers ).

<#author> a acp:AccessControl; 
   acp:apply <#authorPolicy>.

<#authorPolicy> a acp:Policy; 
   acp:allow acl:Read, acl:Write;
   acp:anyOf ( <${resourceAuthor ?? ownerWebId}/profile/card#me> ).
''';
  }

  // Helper method to write ACR
  static Future<void> _writeAcr(String acrUrl, String acrBody) async {
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
      debugPrint('Failed to write ACR to $acrUrl => ${res.statusCode} ${res.body}');
      throw Exception('Failed to write ACR: ${res.statusCode}');
    }
  }

  // Utility methods for checking ACR policies
  static Future<bool> hasValidTimeAccess(String resourceUrl) async {
    try {
      final acrContent = await _fetchAcr(resourceUrl);
      if (acrContent == null) return false;
      
      // Simple check for validUntil
      final validUntilMatch = RegExp(r'ex:validUntil\s+"([^"]+)"').firstMatch(acrContent);
      if (validUntilMatch == null) return true; // No time limit
      
      final validUntil = DateTime.parse(validUntilMatch.group(1)!);
      return DateTime.now().isBefore(validUntil);
    } catch (e) {
      debugPrint('Error checking time access: $e');
      return false;
    }
  }

  static Future<String?> _fetchAcr(String resourceUrl) async {
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
      return res.statusCode == 200 ? res.body : null;
    } catch (e) {
      debugPrint('Error fetching ACR: $e');
      return null;
    }
  }
}

// Enhanced presets for the new use cases
class AcpPresets {
  /// Use Case 1: App-scoped access
  static Future<void> appScopedAccess(String resourceUrl, String ownerWebId, 
      {List<String>? readers}) async {
    await AcpService.writeAppScopedAcr(
      resourceUrl, 
      ownerWebId,
      allowReadWebIds: readers,
    );
  }

  /// Use Case 2: Manager delegation
  static Future<void> managerDelegation(String resourceUrl, String ownerWebId, 
      String managerWebId, {List<String>? contractors}) async {
    await AcpService.writeDelegatedSharingAcr(
      resourceUrl, 
      ownerWebId, 
      managerWebId,
      contractorWebIds: contractors,
    );
  }

  /// Use Case 3: Temporary exam access
  static Future<void> examAccess(String resourceUrl, String ownerWebId, 
      List<String> studentWebIds, {required DateTime examEnd}) async {
    await AcpService.writeTimeLimitedAcr(
      resourceUrl, 
      ownerWebId,
      tempAccessWebIds: studentWebIds,
      validUntil: examEnd,
    );
  }

  /// Use Case 4: Team roles
  static Future<void> teamRoles(String resourceUrl, String ownerWebId) async {
    await AcpService.writeRoleBasedAcr(
      resourceUrl, 
      ownerWebId,
      adminRoles: ['https://org.example.org/roles/admin'],
      reviewerRoles: ['https://org.example.org/roles/reviewer'],
      contributorRoles: ['https://org.example.org/roles/contributor'],
    );
  }
  
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
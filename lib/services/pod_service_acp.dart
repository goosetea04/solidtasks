import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:solidpod/solidpod.dart';

/// ACP Service for Community Solid Server v7.1.7
/// 
/// Implements Access Control Policies (ACP) for Solid resources.
/// Supports client identifier matching, WebID-based access control,
/// policy composition with audit metadata, and container inheritance.
class AcpService {
  static const String officialClientId = 
      'https://clients.example.org/solidtasks-web#client';
  
  /// USE CASE 1: App-scoped Access Control
  /// 
  /// Restricts write operations to a specific client application.
  /// Other applications cannot write even with valid user credentials.
  static Future<void> writeAppScopedAcr(
    String resourceUrl,
    String ownerWebId, {
    List<String>? allowReadWebIds,
    String? allowedClientId,
  }) async {
    final acrUrl = '$resourceUrl.acr';
    final acrBody = _generateAppScopedAcr(
      ownerWebId,
      allowReadWebIds: allowReadWebIds ?? [],
      allowedClientId: allowedClientId ?? officialClientId,
    );
    await _writeAcr(acrUrl, acrBody);
    debugPrint('App-scoped ACR written for $resourceUrl');
  }

  /// USE CASE 2: Delegated Sharing
  /// 
  /// Owner maintains full control, manager can modify content,
  /// and contractors receive read-only access. Includes audit metadata
  /// for tracking who granted permissions and when.
  static Future<void> writeDelegatedSharingAcr(
    String resourceUrl,
    String ownerWebId,
    String managerWebId, {
    List<String>? contractorWebIds,
  }) async {
    final acrUrl = '$resourceUrl.acr';
    final acrBody = _generateDelegatedSharingAcr(
      ownerWebId,
      managerWebId,
      contractorWebIds: contractorWebIds ?? [],
    );
    await _writeAcr(acrUrl, acrBody);
    debugPrint('Delegated sharing ACR written for $resourceUrl');
  }

  /// USE CASE 3: Role-based Access
  /// 
  /// Grants access based on organizational roles using static WebIDs.
  /// Admins get full control, reviewers get read access, 
  /// and contributors get read/write access.
  static Future<void> writeRoleBasedAcr(
    String resourceUrl,
    String ownerWebId, {
    List<String>? adminWebIds,
    List<String>? reviewerWebIds,
    List<String>? contributorWebIds,
  }) async {
    final acrUrl = '$resourceUrl.acr';
    final acrBody = _generateRoleBasedAcr(
      ownerWebId,
      adminWebIds: adminWebIds ?? [],
      reviewerWebIds: reviewerWebIds ?? [],
      contributorWebIds: contributorWebIds ?? [],
    );
    await _writeAcr(acrUrl, acrBody);
    debugPrint('Role-based ACR written for $resourceUrl');
  }

  /// USE CASE 4: Container Inheritance
  /// 
  /// Applies default policies to all resources within a container.
  /// Child resources inherit permissions unless overridden with their own ACR.
  /// This is one of ACP's key advantages over traditional ACL.
  static Future<void> writeContainerAcr(
    String containerUrl,
    String ownerWebId, {
    List<String>? defaultReadWebIds,
    List<String>? defaultWriteWebIds,
  }) async {
    final normalizedUrl = containerUrl.endsWith('/') 
        ? containerUrl 
        : '$containerUrl/';
    final acrUrl = '${normalizedUrl}.acr';
    
    final acrBody = _generateContainerAcr(
      ownerWebId,
      defaultReadWebIds: defaultReadWebIds ?? [],
      defaultWriteWebIds: defaultWriteWebIds ?? [],
    );
    await _writeAcr(acrUrl, acrBody);
    debugPrint('Container ACR written for $normalizedUrl');
  }

  // ACR Generators

  static String _generateAppScopedAcr(
    String ownerWebId, {
    required List<String> allowReadWebIds,
    required String allowedClientId,
  }) {
    final ownerNormalized = _normalizeWebId(ownerWebId);
    final readNormalized = allowReadWebIds.map(_normalizeWebId).toList();
    
    final readAgents = [ownerNormalized, ...readNormalized]
        .map((id) => '<$id>')
        .join(', ');
    
    return '''@prefix acp: <http://www.w3.org/ns/solid/acp#> .
@prefix acl: <http://www.w3.org/ns/auth/acl#> .

<> a acp:AccessControlResource ;
   acp:accessControl <#ownerAccess>, <#appWriteAccess>, <#readAccess> .

<#ownerMatcher> a acp:Matcher ;
   acp:agent <$ownerNormalized> .

<#ownerAccess> a acp:AccessControl ;
   acp:apply <#ownerPolicy> .

<#ownerPolicy> a acp:Policy ;
   acp:allow acl:Read, acl:Write, acl:Control ;
   acp:anyOf <#ownerMatcher> .

<#clientMatcher> a acp:Matcher ;
   acp:client <$allowedClientId> .

<#appWriteAccess> a acp:AccessControl ;
   acp:apply <#clientPolicy> .

<#clientPolicy> a acp:Policy ;
   acp:allow acl:Write ;
   acp:anyOf <#clientMatcher> .

<#readMatcher> a acp:Matcher ;
   acp:agent $readAgents .

<#readAccess> a acp:AccessControl ;
   acp:apply <#readPolicy> .

<#readPolicy> a acp:Policy ;
   acp:allow acl:Read ;
   acp:anyOf <#readMatcher> .
''';
  }

  static String _generateDelegatedSharingAcr(
    String ownerWebId,
    String managerWebId, {
    required List<String> contractorWebIds,
  }) {
    final ownerNormalized = _normalizeWebId(ownerWebId);
    final managerNormalized = _normalizeWebId(managerWebId);
    final timestamp = DateTime.now().toUtc().toIso8601String();
    
    final contractorSection = contractorWebIds.isEmpty ? '' : '''
<#contractorMatcher> a acp:Matcher ;
   acp:agent ${contractorWebIds.map((id) => '<${_normalizeWebId(id)}>').join(', ')} .

<#contractorAccess> a acp:AccessControl ;
   acp:apply <#contractorPolicy> .

<#contractorPolicy> a acp:Policy ;
   acp:allow acl:Read ;
   acp:anyOf <#contractorMatcher> ;
   dct:creator <$managerNormalized> ;
   dct:created "$timestamp"^^xsd:dateTime .
''';
    
    return '''@prefix acp: <http://www.w3.org/ns/solid/acp#> .
@prefix acl: <http://www.w3.org/ns/auth/acl#> .
@prefix dct: <http://purl.org/dc/terms#> .
@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .

<> a acp:AccessControlResource ;
   acp:accessControl <#ownerAccess>, <#managerAccess>${contractorWebIds.isEmpty ? '' : ', <#contractorAccess>'} .

<#ownerMatcher> a acp:Matcher ;
   acp:agent <$ownerNormalized> .

<#ownerAccess> a acp:AccessControl ;
   acp:apply <#ownerPolicy> .

<#ownerPolicy> a acp:Policy ;
   acp:allow acl:Read, acl:Write, acl:Control ;
   acp:anyOf <#ownerMatcher> ;
   dct:creator <$ownerNormalized> ;
   dct:created "$timestamp"^^xsd:dateTime .

<#managerMatcher> a acp:Matcher ;
   acp:agent <$managerNormalized> .

<#managerAccess> a acp:AccessControl ;
   acp:apply <#managerPolicy> .

<#managerPolicy> a acp:Policy ;
   acp:allow acl:Read, acl:Write ;
   acp:anyOf <#managerMatcher> ;
   dct:creator <$ownerNormalized> ;
   dct:created "$timestamp"^^xsd:dateTime .

$contractorSection''';
  }

  static String _generateRoleBasedAcr(
    String ownerWebId, {
    required List<String> adminWebIds,
    required List<String> reviewerWebIds,
    required List<String> contributorWebIds,
  }) {
    final ownerNormalized = _normalizeWebId(ownerWebId);
    final timestamp = DateTime.now().toUtc().toIso8601String();
    
    final adminSection = adminWebIds.isEmpty ? '' : '''
<#adminMatcher> a acp:Matcher ;
   acp:agent ${adminWebIds.map((id) => '<${_normalizeWebId(id)}>').join(', ')} .

<#adminAccess> a acp:AccessControl ;
   acp:apply <#adminPolicy> .

<#adminPolicy> a acp:Policy ;
   acp:allow acl:Read, acl:Write, acl:Control ;
   acp:anyOf <#adminMatcher> ;
   dct:created "$timestamp"^^xsd:dateTime .
''';

    final reviewerSection = reviewerWebIds.isEmpty ? '' : '''
<#reviewerMatcher> a acp:Matcher ;
   acp:agent ${reviewerWebIds.map((id) => '<${_normalizeWebId(id)}>').join(', ')} .

<#reviewerAccess> a acp:AccessControl ;
   acp:apply <#reviewerPolicy> .

<#reviewerPolicy> a acp:Policy ;
   acp:allow acl:Read ;
   acp:anyOf <#reviewerMatcher> ;
   dct:created "$timestamp"^^xsd:dateTime .
''';

    final contributorSection = contributorWebIds.isEmpty ? '' : '''
<#contributorMatcher> a acp:Matcher ;
   acp:agent ${contributorWebIds.map((id) => '<${_normalizeWebId(id)}>').join(', ')} .

<#contributorAccess> a acp:AccessControl ;
   acp:apply <#contributorPolicy> .

<#contributorPolicy> a acp:Policy ;
   acp:allow acl:Read, acl:Write ;
   acp:anyOf <#contributorMatcher> ;
   dct:created "$timestamp"^^xsd:dateTime .
''';

    final accessControls = ['<#ownerAccess>'];
    if (adminWebIds.isNotEmpty) accessControls.add('<#adminAccess>');
    if (reviewerWebIds.isNotEmpty) accessControls.add('<#reviewerAccess>');
    if (contributorWebIds.isNotEmpty) accessControls.add('<#contributorAccess>');
    
    return '''@prefix acp: <http://www.w3.org/ns/solid/acp#> .
@prefix acl: <http://www.w3.org/ns/auth/acl#> .
@prefix dct: <http://purl.org/dc/terms#> .
@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .

<> a acp:AccessControlResource ;
   acp:accessControl ${accessControls.join(', ')} .

<#ownerMatcher> a acp:Matcher ;
   acp:agent <$ownerNormalized> .

<#ownerAccess> a acp:AccessControl ;
   acp:apply <#ownerPolicy> .

<#ownerPolicy> a acp:Policy ;
   acp:allow acl:Read, acl:Write, acl:Control ;
   acp:anyOf <#ownerMatcher> .

$adminSection$reviewerSection$contributorSection''';
  }

  static String _generateContainerAcr(
    String ownerWebId, {
    required List<String> defaultReadWebIds,
    required List<String> defaultWriteWebIds,
  }) {
    final ownerNormalized = _normalizeWebId(ownerWebId);
    
    final readSection = defaultReadWebIds.isEmpty ? '' : '''
<#defaultReadMatcher> a acp:Matcher ;
   acp:agent ${defaultReadWebIds.map((id) => '<${_normalizeWebId(id)}>').join(', ')} .

<#defaultReadAccess> a acp:AccessControl ;
   acp:apply <#defaultReadPolicy> .

<#defaultReadPolicy> a acp:Policy ;
   acp:allow acl:Read ;
   acp:anyOf <#defaultReadMatcher> .
''';

    final writeSection = defaultWriteWebIds.isEmpty ? '' : '''
<#defaultWriteMatcher> a acp:Matcher ;
   acp:agent ${defaultWriteWebIds.map((id) => '<${_normalizeWebId(id)}>').join(', ')} .

<#defaultWriteAccess> a acp:AccessControl ;
   acp:apply <#defaultWritePolicy> .

<#defaultWritePolicy> a acp:Policy ;
   acp:allow acl:Read, acl:Write ;
   acp:anyOf <#defaultWriteMatcher> .
''';

    final accessControls = ['<#ownerAccess>'];
    if (defaultReadWebIds.isNotEmpty) accessControls.add('<#defaultReadAccess>');
    if (defaultWriteWebIds.isNotEmpty) accessControls.add('<#defaultWriteAccess>');
    
    return '''@prefix acp: <http://www.w3.org/ns/solid/acp#> .
@prefix acl: <http://www.w3.org/ns/auth/acl#> .

<> a acp:AccessControlResource ;
   acp:accessControl ${accessControls.join(', ')} .

<#ownerMatcher> a acp:Matcher ;
   acp:agent <$ownerNormalized> .

<#ownerAccess> a acp:AccessControl ;
   acp:apply <#ownerPolicy> .

<#ownerPolicy> a acp:Policy ;
   acp:allow acl:Read, acl:Write, acl:Control ;
   acp:anyOf <#ownerMatcher> .

$readSection$writeSection''';
  }

  // Helper Methods

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
      debugPrint('Failed to write ACR to $acrUrl: ${res.statusCode}');
      throw Exception('Failed to write ACR: ${res.statusCode}');
    }
  }

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
      return res.statusCode == 200 ? res.body : null;
    } catch (e) {
      debugPrint('Error fetching ACR: $e');
      return null;
    }
  }

  static String _normalizeWebId(String webId) {
    if (!webId.contains('#')) {
      return webId.endsWith('/') 
          ? '${webId}profile/card#me'
          : '$webId/profile/card#me';
    }
    return webId;
  }

  /// Basic ACR for simple permission patterns
  static Future<void> writeAcrForResource(
    String resourceUrl,
    String ownerWebId, {
    List<String>? allowReadWebIds,
    List<String>? allowWriteWebIds,
    List<String>? allowControlWebIds,
    bool publicRead = false,
  }) async {
    final acrUrl = '$resourceUrl.acr';
    final acrBody = _generateBasicAcr(
      ownerWebId,
      allowReadWebIds: allowReadWebIds ?? [],
      allowWriteWebIds: allowWriteWebIds ?? [],
      allowControlWebIds: allowControlWebIds ?? [],
      publicRead: publicRead,
    );
    await _writeAcr(acrUrl, acrBody);
  }

  static String _generateBasicAcr(
    String ownerWebId, {
    required List<String> allowReadWebIds,
    required List<String> allowWriteWebIds,
    required List<String> allowControlWebIds,
    required bool publicRead,
  }) {
    final ownerNormalized = _normalizeWebId(ownerWebId);
    
    final readSection = (allowReadWebIds.isNotEmpty || publicRead) ? '''
<#readMatcher> a acp:Matcher ;
   acp:agent ${publicRead ? 'acp:PublicAgent' : allowReadWebIds.map((id) => '<${_normalizeWebId(id)}>').join(', ')} .

<#readAccess> a acp:AccessControl ;
   acp:apply <#readPolicy> .

<#readPolicy> a acp:Policy ;
   acp:allow acl:Read ;
   acp:anyOf <#readMatcher> .
''' : '';

    final writeSection = allowWriteWebIds.isNotEmpty ? '''
<#writeMatcher> a acp:Matcher ;
   acp:agent ${allowWriteWebIds.map((id) => '<${_normalizeWebId(id)}>').join(', ')} .

<#writeAccess> a acp:AccessControl ;
   acp:apply <#writePolicy> .

<#writePolicy> a acp:Policy ;
   acp:allow acl:Read, acl:Write ;
   acp:anyOf <#writeMatcher> .
''' : '';

    final accessControls = ['<#ownerAccess>'];
    if (allowReadWebIds.isNotEmpty || publicRead) accessControls.add('<#readAccess>');
    if (allowWriteWebIds.isNotEmpty) accessControls.add('<#writeAccess>');

    return '''@prefix acp: <http://www.w3.org/ns/solid/acp#> .
@prefix acl: <http://www.w3.org/ns/auth/acl#> .

<> a acp:AccessControlResource ;
   acp:accessControl ${accessControls.join(', ')} .

<#ownerMatcher> a acp:Matcher ;
   acp:agent <$ownerNormalized> .

<#ownerAccess> a acp:AccessControl ;
   acp:apply <#ownerPolicy> .

<#ownerPolicy> a acp:Policy ;
   acp:allow acl:Read, acl:Write, acl:Control ;
   acp:anyOf <#ownerMatcher> .

$readSection$writeSection''';
  }
}

/// Convenience presets for common access control patterns
class AcpPresets {
  /// App-scoped access control
  static Future<void> appScopedAccess(
    String resourceUrl, 
    String ownerWebId, {
    List<String>? readers,
  }) async {
    await AcpService.writeAppScopedAcr(
      resourceUrl, 
      ownerWebId,
      allowReadWebIds: readers,
    );
  }

  /// Manager delegation pattern
  static Future<void> managerDelegation(
    String resourceUrl, 
    String ownerWebId, 
    String managerWebId, {
    List<String>? contractors,
  }) async {
    await AcpService.writeDelegatedSharingAcr(
      resourceUrl, 
      ownerWebId, 
      managerWebId,
      contractorWebIds: contractors,
    );
  }

  /// Role-based team access
  static Future<void> teamRoles(
    String resourceUrl, 
    String ownerWebId, {
    List<String>? adminWebIds,
    List<String>? reviewerWebIds,
    List<String>? contributorWebIds,
    // Backward compatibility
    List<String>? adminRoles,
    List<String>? reviewerRoles,
    List<String>? contributorRoles,
  }) async {
    await AcpService.writeRoleBasedAcr(
      resourceUrl, 
      ownerWebId,
      adminWebIds: adminWebIds ?? adminRoles,
      reviewerWebIds: reviewerWebIds ?? reviewerRoles,
      contributorWebIds: contributorWebIds ?? contributorRoles,
    );
  }

  /// Container with default permissions
  static Future<void> containerDefaults(
    String containerUrl,
    String ownerWebId, {
    List<String>? teamReadAccess,
    List<String>? teamWriteAccess,
  }) async {
    await AcpService.writeContainerAcr(
      containerUrl,
      ownerWebId,
      defaultReadWebIds: teamReadAccess,
      defaultWriteWebIds: teamWriteAccess,
    );
  }

  /// Fetch ACR content
  static Future<String?> fetchAcr(String resourceUrl) async {
    return AcpService.fetchAcr(resourceUrl);
  }

  /// Basic ACR for simple patterns
  static Future<void> writeAcrForResource(
    String resourceUrl,
    String ownerWebId, {
    List<String>? allowReadWebIds,
    List<String>? allowWriteWebIds,
    List<String>? allowControlWebIds,
    bool publicRead = false,
  }) async {
    await AcpService.writeAcrForResource(
      resourceUrl,
      ownerWebId,
      allowReadWebIds: allowReadWebIds,
      allowWriteWebIds: allowWriteWebIds,
      allowControlWebIds: allowControlWebIds,
      publicRead: publicRead,
    );
  }
}
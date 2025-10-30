import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:solidpod/solidpod.dart';
import '../utils/pod_utils.dart';
import 'policy_manager.dart';
import 'permission_log_service.dart';

/// Streamlined ACP Service using Centralized Policies
/// 
/// This service has been simplified to use PolicyManager for reusable policies.
/// Instead of generating ACRs inline, it references centralized policy files.
/// All policy applications are automatically logged via PermissionLogService.
class AcpService {
  static const String officialClientId = 
      'https://clients.example.org/solidtasks-web#client';
  
  /// Apply owner-only access (private resource)
  static Future<void> applyOwnerOnly(
    String resourceUrl,
    String ownerWebId,
  ) async {
    await PolicyManager.applyPolicyToResource(
      resourceUrl: resourceUrl,
      policyFileName: PolicyManager.ownerOnlyPolicy,
      ownerWebId: ownerWebId,
    );
    
    // Log using the helper method
    await PermissionLogService.logOwnerOnlyPolicy(
      resourceUrl: resourceUrl,
      ownerWebId: ownerWebId,
    );
    
    debugPrint('(check) Applied owner-only policy to $resourceUrl');
  }
  
  /// Apply shared read access (owner + readers)
  static Future<void> applySharedRead(
    String resourceUrl,
    String ownerWebId,
    List<String> readerWebIds,
  ) async {
    await PolicyManager.applyPolicyToResource(
      resourceUrl: resourceUrl,
      policyFileName: PolicyManager.sharedReadPolicy,
      ownerWebId: ownerWebId,
      additionalReaders: readerWebIds,
    );
    
    // Log using the helper method
    await PermissionLogService.logSharedReadPolicy(
      resourceUrl: resourceUrl,
      ownerWebId: ownerWebId,
      readerWebIds: readerWebIds,
    );
    
    debugPrint('(check) Applied shared-read policy to $resourceUrl');
  }
  
  /// Apply shared write access (owner + collaborators)
  static Future<void> applySharedWrite(
    String resourceUrl,
    String ownerWebId,
    List<String> writerWebIds,
  ) async {
    await PolicyManager.applyPolicyToResource(
      resourceUrl: resourceUrl,
      policyFileName: PolicyManager.sharedWritePolicy,
      ownerWebId: ownerWebId,
      additionalWriters: writerWebIds,
    );
    
    // Log using the helper method
    await PermissionLogService.logSharedWritePolicy(
      resourceUrl: resourceUrl,
      ownerWebId: ownerWebId,
      writerWebIds: writerWebIds,
    );
    
    debugPrint('(check) Applied shared-write policy to $resourceUrl');
  }
  
  /// Apply team collaboration access (owner + admins + editors + viewers)
  static Future<void> applyTeamCollab(
    String resourceUrl,
    String ownerWebId, {
    List<String>? adminWebIds,
    List<String>? editorWebIds,
    List<String>? viewerWebIds,
  }) async {
    await PolicyManager.applyPolicyToResource(
      resourceUrl: resourceUrl,
      policyFileName: PolicyManager.teamCollabPolicy,
      ownerWebId: ownerWebId,
      admins: adminWebIds,
      editors: editorWebIds,
      viewers: viewerWebIds,
    );
    
    // Log using the helper method
    await PermissionLogService.logTeamCollabPolicy(
      resourceUrl: resourceUrl,
      ownerWebId: ownerWebId,
      adminWebIds: adminWebIds,
      editorWebIds: editorWebIds,
      viewerWebIds: viewerWebIds,
    );
    
    debugPrint('(check) Applied team-collab policy to $resourceUrl');
  }
  
  /// Apply public read access (anyone can read)
  static Future<void> applyPublicRead(
    String resourceUrl,
    String ownerWebId,
  ) async {
    await PolicyManager.applyPolicyToResource(
      resourceUrl: resourceUrl,
      policyFileName: PolicyManager.publicReadPolicy,
      ownerWebId: ownerWebId,
    );
    
    // Log using the helper method
    await PermissionLogService.logPublicReadPolicy(
      resourceUrl: resourceUrl,
      ownerWebId: ownerWebId,
    );
    
    debugPrint('(check) Applied public-read policy to $resourceUrl');
  }
  
  /// Fetch ACR content for a resource
  static Future<String?> fetchAcr(String resourceUrl) async {
    try {
      final acrUrl = '$resourceUrl.acr';
      return await PodUtils.readTurtleContent(acrUrl);
    } catch (e) {
      debugPrint('Error fetching ACR: $e');
      return null;
    }
  }
  
  /// Remove all access control (delete ACR)
  static Future<void> removeAccessControl(String resourceUrl) async {
    try {
      await PodUtils.deleteResource('$resourceUrl.acr');
      debugPrint('(check) Removed access control from $resourceUrl');
    } catch (e) {
      debugPrint('Error removing access control: $e');
      rethrow;
    }
  }
  
  // ============================================================================
  // LEGACY INLINE ACR METHODS (For backward compatibility)
  static Future<void> writeInlineAcr(
    String resourceUrl,
    String ownerWebId, {
    List<String>? allowReadWebIds,
    List<String>? allowWriteWebIds,
    List<String>? allowControlWebIds,
    bool publicRead = false,
  }) async {
    final acrUrl = '$resourceUrl.acr';
    final acrBody = _generateInlineAcr(
      ownerWebId,
      allowReadWebIds: allowReadWebIds ?? [],
      allowWriteWebIds: allowWriteWebIds ?? [],
      allowControlWebIds: allowControlWebIds ?? [],
      publicRead: publicRead,
    );
    await _writeAcr(acrUrl, acrBody);
    debugPrint('warning  Created inline ACR (consider using centralized policies)');
  }
  
  /// Generate inline ACR body (DEPRECATED)
  static String _generateInlineAcr(
    String ownerWebId, {
    required List<String> allowReadWebIds,
    required List<String> allowWriteWebIds,
    required List<String> allowControlWebIds,
    required bool publicRead,
  }) {
    final ownerNormalized = PodUtils.normalizeWebId(ownerWebId);
    
    final readSection = (allowReadWebIds.isNotEmpty || publicRead) ? '''
<#readMatcher> a acp:Matcher ;
   acp:agent ${publicRead ? 'acp:PublicAgent' : allowReadWebIds.map((id) => '<${PodUtils.normalizeWebId(id)}>').join(', ')} .

<#readAccess> a acp:AccessControl ;
   acp:apply <#readPolicy> .

<#readPolicy> a acp:Policy ;
   acp:allow acl:Read ;
   acp:anyOf <#readMatcher> .
''' : '';

    final writeSection = allowWriteWebIds.isNotEmpty ? '''
<#writeMatcher> a acp:Matcher ;
   acp:agent ${allowWriteWebIds.map((id) => '<${PodUtils.normalizeWebId(id)}>').join(', ')} .

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
  
  /// Write ACR to server
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
}

/// Simplified Presets using Centralized Policies
/// 
/// These provide convenient shortcuts for common access patterns.
/// All methods use PolicyManager under the hood.
class AcpPresets {
  /// Apply owner-only access (private)
  static Future<void> privateResource(
    String resourceUrl, 
    String ownerWebId,
  ) async {
    await AcpService.applyOwnerOnly(resourceUrl, ownerWebId);
  }
  
  /// Share with read-only access
  static Future<void> shareReadOnly(
    String resourceUrl, 
    String ownerWebId,
    List<String> readerWebIds,
  ) async {
    await AcpService.applySharedRead(resourceUrl, ownerWebId, readerWebIds);
  }
  
  /// Share with read-write access
  static Future<void> shareReadWrite(
    String resourceUrl, 
    String ownerWebId,
    List<String> writerWebIds,
  ) async {
    await AcpService.applySharedWrite(resourceUrl, ownerWebId, writerWebIds);
  }
  
  /// Team collaboration with roles
  static Future<void> teamAccess(
    String resourceUrl, 
    String ownerWebId, {
    List<String>? admins,
    List<String>? editors,
    List<String>? viewers,
  }) async {
    await AcpService.applyTeamCollab(
      resourceUrl,
      ownerWebId,
      adminWebIds: admins,
      editorWebIds: editors,
      viewerWebIds: viewers,
    );
  }
  
  /// Make resource publicly readable
  static Future<void> publicResource(
    String resourceUrl, 
    String ownerWebId,
  ) async {
    await AcpService.applyPublicRead(resourceUrl, ownerWebId);
  }
  
  /// Fetch ACR content
  static Future<String?> fetchAcr(String resourceUrl) async {
    return AcpService.fetchAcr(resourceUrl);
  }
  
  /// Basic ACR for simple patterns (DEPRECATED - use centralized policies)
  /// 
  /// This method exists for backward compatibility only.
  /// New code should use PolicyManager.applyPolicyToResource() instead.
  @Deprecated('Use PolicyManager.applyPolicyToResource() with centralized policies')
  static Future<void> writeAcrForResource(
    String resourceUrl,
    String ownerWebId, {
    List<String>? allowReadWebIds,
    List<String>? allowWriteWebIds,
    List<String>? allowControlWebIds,
    bool publicRead = false,
  }) async {
    // For backward compatibility, map to new methods when possible
    if (publicRead && 
        (allowReadWebIds?.isEmpty ?? true) && 
        (allowWriteWebIds?.isEmpty ?? true) && 
        (allowControlWebIds?.isEmpty ?? true)) {
      // Public read only
      await AcpService.applyPublicRead(resourceUrl, ownerWebId);
    } else if ((allowReadWebIds?.isNotEmpty ?? false) && 
               (allowWriteWebIds?.isEmpty ?? true) && 
               (allowControlWebIds?.isEmpty ?? true)) {
      // Shared read only
      await AcpService.applySharedRead(resourceUrl, ownerWebId, allowReadWebIds!);
    } else if ((allowWriteWebIds?.isNotEmpty ?? false) && 
               (allowControlWebIds?.isEmpty ?? true)) {
      // Shared write
      await AcpService.applySharedWrite(resourceUrl, ownerWebId, allowWriteWebIds!);
    } else {
      // Complex case - fall back to inline ACR
      await AcpService.writeInlineAcr(
        resourceUrl,
        ownerWebId,
        allowReadWebIds: allowReadWebIds,
        allowWriteWebIds: allowWriteWebIds,
        allowControlWebIds: allowControlWebIds,
        publicRead: publicRead,
      );
    }
  }
  
  // Legacy method names for backward compatibility
  
  @Deprecated('Use AcpPresets.shareReadOnly() instead')
  static Future<void> appScopedAccess(
    String resourceUrl, 
    String ownerWebId, {
    List<String>? readers,
  }) async {
    if (readers != null && readers.isNotEmpty) {
      await shareReadOnly(resourceUrl, ownerWebId, readers);
    } else {
      await privateResource(resourceUrl, ownerWebId);
    }
  }
  
  @Deprecated('Use AcpPresets.shareReadWrite() with managers as writers')
  static Future<void> managerDelegation(
    String resourceUrl, 
    String ownerWebId, 
    String managerWebId, {
    List<String>? contractors,
  }) async {
    await shareReadWrite(resourceUrl, ownerWebId, [managerWebId]);
  }
  
  @Deprecated('Use AcpPresets.teamAccess() instead')
  static Future<void> teamRoles(
    String resourceUrl, 
    String ownerWebId, {
    List<String>? adminWebIds,
    List<String>? reviewerWebIds,
    List<String>? contributorWebIds,
    List<String>? adminRoles,
    List<String>? reviewerRoles,
    List<String>? contributorRoles,
  }) async {
    await teamAccess(
      resourceUrl,
      ownerWebId,
      admins: adminWebIds ?? adminRoles,
      viewers: reviewerWebIds ?? reviewerRoles,
      editors: contributorWebIds ?? contributorRoles,
    );
  }
  
  @Deprecated('Use AcpService.applyPublicRead() or AcpService.applySharedRead()')
  static Future<void> containerDefaults(
    String containerUrl,
    String ownerWebId, {
    List<String>? teamReadAccess,
    List<String>? teamWriteAccess,
  }) async {
    if (teamWriteAccess != null && teamWriteAccess.isNotEmpty) {
      await shareReadWrite(containerUrl, ownerWebId, teamWriteAccess);
    } else if (teamReadAccess != null && teamReadAccess.isNotEmpty) {
      await shareReadOnly(containerUrl, ownerWebId, teamReadAccess);
    } else {
      await privateResource(containerUrl, ownerWebId);
    }
  }
}
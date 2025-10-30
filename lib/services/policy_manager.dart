import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:solidpod/solidpod.dart';
import '../utils/pod_utils.dart';

/// Centralized Policy Manager for ACP
class PolicyManager {
  static const String policiesDirRel = '/solidtasks/policies/';
  
  // Standard policy file names
  static const String ownerOnlyPolicy = 'owner-only.ttl';
  static const String sharedReadPolicy = 'shared-read.ttl';
  static const String sharedWritePolicy = 'shared-write.ttl';
  static const String teamCollabPolicy = 'team-collab.ttl';
  static const String publicReadPolicy = 'public-read.ttl';
  
  /// Initialize the policies directory and create standard policies
  static Future<void> initializePolicies(String ownerWebId) async {
    try {
      debugPrint('🔧 Initializing centralized policies...');
      
      // Ensure policies directory exists
      final webId = await PodUtils.getCurrentWebIdClean();
      final policiesDir = '$webId$policiesDirRel';
      await PodUtils.ensureDirectoryExists(policiesDir);
      
      // Create standard policy files
      await _createOwnerOnlyPolicy(policiesDir, ownerWebId);
      await _createSharedReadPolicy(policiesDir, ownerWebId);
      await _createSharedWritePolicy(policiesDir, ownerWebId);
      await _createTeamCollabPolicy(policiesDir, ownerWebId);
      await _createPublicReadPolicy(policiesDir, ownerWebId);
      
      // Set ACR for policies directory (owner-only access)
      await _setPoliciesDirAcr(policiesDir, ownerWebId);
      
      debugPrint('(check) Policies initialized successfully');
    } catch (e) {
      debugPrint('(false) Error initializing policies: $e');
      rethrow;
    }
  }
  
  /// Get the full URI for a policy file
  static Future<String> getPolicyUri(String policyFileName) async {
    final webId = await PodUtils.getCurrentWebIdClean();
    return '$webId$policiesDirRel$policyFileName';
  }
  
  /// Create "Owner Only" policy - full control for owner
  static Future<void> _createOwnerOnlyPolicy(String policiesDir, String ownerWebId) async {
    final policyUrl = '$policiesDir$ownerOnlyPolicy';
    
    // Check if already exists
    if (await PodUtils.checkResourceExists(policyUrl)) {
      debugPrint('Policy already exists: $ownerOnlyPolicy');
      return;
    }
    
    final ownerNormalized = PodUtils.normalizeWebId(ownerWebId);
    
    final policyContent = '''@prefix acp: <http://www.w3.org/ns/solid/acp#> .
@prefix acl: <http://www.w3.org/ns/auth/acl#> .

# Owner-Only Policy
# Grants full control (Read, Write, Control) to the resource owner

<#ownerMatcher> a acp:Matcher ;
    acp:agent <$ownerNormalized> .

<#ownerPolicy> a acp:Policy ;
    acp:allow acl:Read, acl:Write, acl:Control ;
    acp:anyOf <#ownerMatcher> .
''';

    await _writePolicy(policyUrl, policyContent);
    debugPrint('- Created: $ownerOnlyPolicy');
  }
  
  /// Create "Shared Read" policy - owner + specific readers
  static Future<void> _createSharedReadPolicy(String policiesDir, String ownerWebId) async {
    final policyUrl = '$policiesDir$sharedReadPolicy';
    
    if (await PodUtils.checkResourceExists(policyUrl)) {
      debugPrint('Policy already exists: $sharedReadPolicy');
      return;
    }
    
    final ownerNormalized = PodUtils.normalizeWebId(ownerWebId);
    
    final policyContent = '''@prefix acp: <http://www.w3.org/ns/solid/acp#> .
@prefix acl: <http://www.w3.org/ns/auth/acl#> .

# Shared Read Policy
# Owner has full control, specified agents can read
# Note: Specific readers are added via ACR that references this policy

<#ownerMatcher> a acp:Matcher ;
    acp:agent <$ownerNormalized> .

<#ownerPolicy> a acp:Policy ;
    acp:allow acl:Read, acl:Write, acl:Control ;
    acp:anyOf <#ownerMatcher> .

<#readerPolicy> a acp:Policy ;
    acp:allow acl:Read ;
    acp:anyOf <#readerMatcher> .

<#readerMatcher> a acp:Matcher .
# Readers will be specified in the ACR that applies this policy
''';

    await _writePolicy(policyUrl, policyContent);
    debugPrint('- Created: $sharedReadPolicy');
  }
  
  /// Create "Shared Write" policy - owner + collaborators who can read/write
  static Future<void> _createSharedWritePolicy(String policiesDir, String ownerWebId) async {
    final policyUrl = '$policiesDir$sharedWritePolicy';
    
    if (await PodUtils.checkResourceExists(policyUrl)) {
      debugPrint('Policy already exists: $sharedWritePolicy');
      return;
    }
    
    final ownerNormalized = PodUtils.normalizeWebId(ownerWebId);
    
    final policyContent = '''@prefix acp: <http://www.w3.org/ns/solid/acp#> .
@prefix acl: <http://www.w3.org/ns/auth/acl#> .

# Shared Write Policy
# Owner has full control, specified agents can read and write

<#ownerMatcher> a acp:Matcher ;
    acp:agent <$ownerNormalized> .

<#ownerPolicy> a acp:Policy ;
    acp:allow acl:Read, acl:Write, acl:Control ;
    acp:anyOf <#ownerMatcher> .

<#collaboratorPolicy> a acp:Policy ;
    acp:allow acl:Read, acl:Write ;
    acp:anyOf <#collaboratorMatcher> .

<#collaboratorMatcher> a acp:Matcher .
# Collaborators will be specified in the ACR that applies this policy
''';

    await _writePolicy(policyUrl, policyContent);
    debugPrint('- Created: $sharedWritePolicy');
  }
  
  /// Create "Team Collaboration" policy - multiple roles
  static Future<void> _createTeamCollabPolicy(String policiesDir, String ownerWebId) async {
    final policyUrl = '$policiesDir$teamCollabPolicy';
    
    if (await PodUtils.checkResourceExists(policyUrl)) {
      debugPrint('Policy already exists: $teamCollabPolicy');
      return;
    }
    
    final ownerNormalized = PodUtils.normalizeWebId(ownerWebId);
    
    final policyContent = '''@prefix acp: <http://www.w3.org/ns/solid/acp#> .
@prefix acl: <http://www.w3.org/ns/auth/acl#> .

# Team Collaboration Policy
# Supports multiple roles: owner, admins, editors, viewers

<#ownerMatcher> a acp:Matcher ;
    acp:agent <$ownerNormalized> .

<#ownerPolicy> a acp:Policy ;
    acp:allow acl:Read, acl:Write, acl:Control ;
    acp:anyOf <#ownerMatcher> .

<#adminPolicy> a acp:Policy ;
    acp:allow acl:Read, acl:Write, acl:Control ;
    acp:anyOf <#adminMatcher> .

<#editorPolicy> a acp:Policy ;
    acp:allow acl:Read, acl:Write ;
    acp:anyOf <#editorMatcher> .

<#viewerPolicy> a acp:Policy ;
    acp:allow acl:Read ;
    acp:anyOf <#viewerMatcher> .

<#adminMatcher> a acp:Matcher .
<#editorMatcher> a acp:Matcher .
<#viewerMatcher> a acp:Matcher .
# Role members will be specified in the ACR that applies this policy
''';

    await _writePolicy(policyUrl, policyContent);
    debugPrint('- Created: $teamCollabPolicy');
  }
  
  /// Create "Public Read" policy - anyone can read
  static Future<void> _createPublicReadPolicy(String policiesDir, String ownerWebId) async {
    final policyUrl = '$policiesDir$publicReadPolicy';
    
    if (await PodUtils.checkResourceExists(policyUrl)) {
      debugPrint('Policy already exists: $publicReadPolicy');
      return;
    }
    
    final ownerNormalized = PodUtils.normalizeWebId(ownerWebId);
    
    final policyContent = '''@prefix acp: <http://www.w3.org/ns/solid/acp#> .
@prefix acl: <http://www.w3.org/ns/auth/acl#> .

# Public Read Policy
# Owner has full control, everyone can read

<#ownerMatcher> a acp:Matcher ;
    acp:agent <$ownerNormalized> .

<#ownerPolicy> a acp:Policy ;
    acp:allow acl:Read, acl:Write, acl:Control ;
    acp:anyOf <#ownerMatcher> .

<#publicMatcher> a acp:Matcher ;
    acp:agent acp:PublicAgent .

<#publicPolicy> a acp:Policy ;
    acp:allow acl:Read ;
    acp:anyOf <#publicMatcher> .
''';

    await _writePolicy(policyUrl, policyContent);
    debugPrint('- Created: $publicReadPolicy');
  }
  
  /// Write a policy file to the pod
  static Future<void> _writePolicy(String policyUrl, String content) async {
    final (:accessToken, :dPopToken) = await getTokensForResource(policyUrl, 'PUT');
    
    final response = await http.put(
      Uri.parse(policyUrl),
      headers: {
        'Content-Type': 'text/turtle',
        'Authorization': 'DPoP $accessToken',
        'DPoP': dPopToken,
      },
      body: content,
    );
    
    if (![200, 201, 204, 205].contains(response.statusCode)) {
      throw Exception('Failed to write policy: ${response.statusCode}');
    }
  }
  
  /// Set ACR for the policies directory (owner-only access)
  static Future<void> _setPoliciesDirAcr(String policiesDir, String ownerWebId) async {
    final normalizedDir = policiesDir.endsWith('/') ? policiesDir : '$policiesDir/';
    final acrUrl = '${normalizedDir}.acr';
    final ownerNormalized = PodUtils.normalizeWebId(ownerWebId);
    
    final acrContent = '''@prefix acp: <http://www.w3.org/ns/solid/acp#> .
@prefix acl: <http://www.w3.org/ns/auth/acl#> .

<> a acp:AccessControlResource ;
   acp:accessControl <#ownerAccess> .

<#ownerMatcher> a acp:Matcher ;
   acp:agent <$ownerNormalized> .

<#ownerAccess> a acp:AccessControl ;
   acp:apply <#ownerPolicy> .

<#ownerPolicy> a acp:Policy ;
   acp:allow acl:Read, acl:Write, acl:Control ;
   acp:anyOf <#ownerMatcher> .
''';
    
    final (:accessToken, :dPopToken) = await getTokensForResource(acrUrl, 'PUT');
    
    final response = await http.put(
      Uri.parse(acrUrl),
      headers: {
        'Content-Type': 'text/turtle',
        'Authorization': 'DPoP $accessToken',
        'DPoP': dPopToken,
      },
      body: acrContent,
    );
    
    if (![200, 201, 204, 205].contains(response.statusCode)) {
      throw Exception('Failed to set policies directory ACR: ${response.statusCode}');
    }
  }
  
  /// Create an ACR that references a centralized policy
  /// This is what you attach to each resource (task)
  static Future<void> applyPolicyToResource({
    required String resourceUrl,
    required String policyFileName,
    required String ownerWebId,
    List<String>? additionalReaders,
    List<String>? additionalWriters,
    List<String>? admins,
    List<String>? editors,
    List<String>? viewers,
  }) async {
    final policyUri = await getPolicyUri(policyFileName);
    final acrUrl = '$resourceUrl.acr';
    final ownerNormalized = PodUtils.normalizeWebId(ownerWebId);
    
    // Build matcher sections for additional permissions
    String additionalMatchers = '';
    String additionalControls = '';
    
    if (additionalReaders != null && additionalReaders.isNotEmpty) {
      final readerAgents = additionalReaders.map((id) => '<${PodUtils.normalizeWebId(id)}>').join(', ');
      additionalMatchers += '''
<#readerMatcher> a acp:Matcher ;
    acp:agent $readerAgents .
''';
      additionalControls += ', <#readerAccess>';
    }
    
    if (additionalWriters != null && additionalWriters.isNotEmpty) {
      final writerAgents = additionalWriters.map((id) => '<${PodUtils.normalizeWebId(id)}>').join(', ');
      additionalMatchers += '''
<#collaboratorMatcher> a acp:Matcher ;
    acp:agent $writerAgents .
''';
      additionalControls += ', <#collaboratorAccess>';
    }
    
    // For team collaboration policy
    if (admins != null && admins.isNotEmpty) {
      final adminAgents = admins.map((id) => '<${PodUtils.normalizeWebId(id)}>').join(', ');
      additionalMatchers += '''
<#adminMatcher> a acp:Matcher ;
    acp:agent $adminAgents .
''';
      additionalControls += ', <#adminAccess>';
    }
    
    if (editors != null && editors.isNotEmpty) {
      final editorAgents = editors.map((id) => '<${PodUtils.normalizeWebId(id)}>').join(', ');
      additionalMatchers += '''
<#editorMatcher> a acp:Matcher ;
    acp:agent $editorAgents .
''';
      additionalControls += ', <#editorAccess>';
    }
    
    if (viewers != null && viewers.isNotEmpty) {
      final viewerAgents = viewers.map((id) => '<${PodUtils.normalizeWebId(id)}>').join(', ');
      additionalMatchers += '''
<#viewerMatcher> a acp:Matcher ;
    acp:agent $viewerAgents .
''';
      additionalControls += ', <#viewerAccess>';
    }
    
    // Create ACR that references the external policy
    final acrContent = '''@prefix acp: <http://www.w3.org/ns/solid/acp#> .
@prefix acl: <http://www.w3.org/ns/auth/acl#> .

<> a acp:AccessControlResource ;
   acp:accessControl <#mainAccess>$additionalControls .

# Reference the external policy file
<#mainAccess> a acp:AccessControl ;
   acp:apply <$policyUri#ownerPolicy> .

$additionalMatchers
${additionalReaders != null && additionalReaders.isNotEmpty ? '''
<#readerAccess> a acp:AccessControl ;
   acp:apply <$policyUri#readerPolicy> .
''' : ''}${additionalWriters != null && additionalWriters.isNotEmpty ? '''
<#collaboratorAccess> a acp:AccessControl ;
   acp:apply <$policyUri#collaboratorPolicy> .
''' : ''}${admins != null && admins.isNotEmpty ? '''
<#adminAccess> a acp:AccessControl ;
   acp:apply <$policyUri#adminPolicy> .
''' : ''}${editors != null && editors.isNotEmpty ? '''
<#editorAccess> a acp:AccessControl ;
   acp:apply <$policyUri#editorPolicy> .
''' : ''}${viewers != null && viewers.isNotEmpty ? '''
<#viewerAccess> a acp:AccessControl ;
   acp:apply <$policyUri#viewerPolicy> .
''' : ''}''';
    
    final (:accessToken, :dPopToken) = await getTokensForResource(acrUrl, 'PUT');
    
    final response = await http.put(
      Uri.parse(acrUrl),
      headers: {
        'Content-Type': 'text/turtle',
        'Authorization': 'DPoP $accessToken',
        'DPoP': dPopToken,
      },
      body: acrContent,
    );
    
    if (![200, 201, 204, 205].contains(response.statusCode)) {
      debugPrint('Failed to apply policy to resource: ${response.statusCode}');
      throw Exception('Failed to apply policy: ${response.statusCode}');
    }
    
    debugPrint('✅ Applied policy $policyFileName to $resourceUrl');
  }
}
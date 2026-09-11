/// Data models matching the Go backend JSON responses.

class Node {
  final String id;
  final String ip;
  final String role;
  final String status;
  final Map<String, dynamic> labels;
  final String caddyStatus;
  final String caddyfile;
  final String createdAt;
  final String updatedAt;

  final double cpuPercent;
  final int memUsedBytes;
  final int memTotalBytes;
  final double memPercent;
  final int diskUsedBytes;
  final int diskTotalBytes;
  final int diskFreeBytes;
  final double diskPercent;
  final double netBps;

  final bool authMismatch;

  Node({
    required this.id,
    required this.ip,
    required this.role,
    required this.status,
    this.labels = const {},
    this.caddyStatus = '',
    this.caddyfile = '',
    this.authMismatch = false,
    this.createdAt = '',
    this.updatedAt = '',
    this.cpuPercent = 0.0,
    this.memUsedBytes = 0,
    this.memTotalBytes = 0,
    this.memPercent = 0.0,
    this.diskUsedBytes = 0,
    this.diskTotalBytes = 0,
    this.diskFreeBytes = 0,
    this.diskPercent = 0.0,
    this.netBps = 0.0,
  });

  factory Node.fromJson(Map<String, dynamic> json) {
    return Node(
      id: json['id'] ?? '',
      ip: json['ip'] ?? '',
      role: json['role'] ?? '',
      status: json['status'] ?? '',
      labels: json['labels'] ?? {},
      caddyStatus: json['caddy_status'] ?? '',
      caddyfile: json['caddyfile'] ?? '',
      authMismatch: json['auth_mismatch'] == true,
      createdAt: json['created_at'] ?? '',
      updatedAt: json['updated_at'] ?? '',
      cpuPercent: (json['cpu_percent'] as num?)?.toDouble() ?? 0.0,
      memUsedBytes: (json['mem_used_bytes'] as num?)?.toInt() ?? 0,
      memTotalBytes: (json['mem_total_bytes'] as num?)?.toInt() ?? 0,
      memPercent: (json['mem_percent'] as num?)?.toDouble() ?? 0.0,
      diskUsedBytes: (json['disk_used_bytes'] as num?)?.toInt() ?? 0,
      diskTotalBytes: (json['disk_total_bytes'] as num?)?.toInt() ?? 0,
      diskFreeBytes: (json['disk_free_bytes'] as num?)?.toInt() ?? 0,
      diskPercent: (json['disk_percent'] as num?)?.toDouble() ?? 0.0,
      netBps: (json['net_bps'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class StackModel {
  final String id;
  final String name;
  final String rawComposeFile;
  final String nodeId;
  final String createdAt;

  StackModel({
    required this.id,
    required this.name,
    this.rawComposeFile = '',
    this.nodeId = '',
    this.createdAt = '',
  });

  factory StackModel.fromJson(Map<String, dynamic> json) {
    return StackModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      rawComposeFile: json['raw_compose_file'] ?? '',
      nodeId: json['node_id'] ?? '',
      createdAt: json['created_at'] ?? '',
    );
  }

  bool hasAutoscaling(List<Service> services) {
    return services.any((s) => s.stackId == id && s.isAutoscalingEnabled);
  }

  Service? primaryAutoscaleService(List<Service> services) {
    final list = services.where((s) => s.stackId == id && s.isAutoscalingEnabled).toList();
    if (list.isEmpty) return null;
    // Prefer GPU service if any, else first
    return list.firstWhere((s) => s.autoscaleMetric == 'gpu', orElse: () => list.first);
  }
}

class Service {
  final String id;
  final String stackId;
  final String name;
  final String image;
  final int desiredReplicas;
  final List<String> constraints;
  final List<String> ports;
  final String cpuLimit;
  final String memoryLimit;
  final String cpuReservation;
  final String memoryReservation;

  Service({
    required this.id,
    required this.stackId,
    required this.name,
    required this.image,
    this.desiredReplicas = 1,
    this.constraints = const [],
    this.ports = const [],
    this.cpuLimit = '',
    this.memoryLimit = '',
    this.cpuReservation = '',
    this.memoryReservation = '',
  });

  factory Service.fromJson(Map<String, dynamic> json) {
    return Service(
      id: json['id'] ?? '',
      stackId: json['stack_id'] ?? '',
      name: json['name'] ?? '',
      image: json['image'] ?? '',
      desiredReplicas: json['desired_replicas'] ?? 1,
      constraints: (json['constraints'] as List?)?.map((e) => e.toString()).toList() ?? [],
      ports: (json['ports'] as List?)?.map((e) => e.toString()).toList() ?? [],
      cpuLimit: json['cpu_limit'] ?? '',
      memoryLimit: json['memory_limit'] ?? '',
      cpuReservation: json['cpu_reservation'] ?? '',
      memoryReservation: json['memory_reservation'] ?? '',
    );
  }

  bool get isAutoscalingEnabled {
    for (final c in constraints) {
      final lower = c.toLowerCase().trim();
      if (lower == 'gbnt.autoscaling.enable=true' ||
          lower == 'gbnt.autoscaling.enable: true' ||
          lower == 'gbnt.autoscaling.enable=1' ||
          lower == 'gbnt.autoscaling.enable=yes') {
        return true;
      }
    }
    return false;
  }

  String get autoscaleScope {
    // Check single-host affinity overrides first
    for (final c in constraints) {
      final lower = c.toLowerCase().trim();
      if (lower.contains('gbnt.placement.strategy=single-host') ||
          lower.contains('node.hostname ==') ||
          lower.contains('gbnt.node.hostname ==')) {
        return 'host';
      }
    }
    for (final c in constraints) {
      final lower = c.toLowerCase().trim();
      if (lower.startsWith('gbnt.autoscaling.scope=')) {
        final val = lower.split('=').last.trim();
        if (val == 'cluster' || val == 'all' || val == 'multi-host') {
          return 'cluster';
        }
        return 'host';
      }
      if (lower.contains('gbnt.placement.strategy=spread') ||
          lower.contains('gbnt.placement.strategy=multi-host')) {
        return 'cluster';
      }
    }
    return 'host';
  }

  String get autoscaleMetric {
    for (final c in constraints) {
      final lower = c.toLowerCase().trim();
      if (lower.startsWith('gbnt.autoscaling.metric=')) {
        final val = lower.split('=').last.trim();
        if (val.contains('gpu') || val.contains('cuda') || val.contains('nvidia')) {
          return 'gpu';
        }
        return 'cpu';
      }
      if (lower.contains('gpu') || lower.contains('nvidia') || lower.contains('cuda')) {
        return 'gpu';
      }
    }
    return 'cpu';
  }

  double get autoscaleTarget {
    for (final c in constraints) {
      final lower = c.toLowerCase().trim();
      if (lower.startsWith('gbnt.autoscaling.target=')) {
        final val = double.tryParse(lower.split('=').last.trim());
        if (val != null && val > 0) return val;
      }
    }
    return 80.0;
  }

  int get autoscaleMin {
    for (final c in constraints) {
      final lower = c.toLowerCase().trim();
      if (lower.startsWith('gbnt.autoscaling.min=')) {
        final val = int.tryParse(lower.split('=').last.trim());
        if (val != null && val >= 1) return val;
      }
    }
    return 1;
  }

  int get autoscaleMax {
    for (final c in constraints) {
      final lower = c.toLowerCase().trim();
      if (lower.startsWith('gbnt.autoscaling.max=')) {
        final val = int.tryParse(lower.split('=').last.trim());
        if (val != null && val >= 1) return val;
      }
    }
    return 5;
  }

  String get autoscaleCooldown {
    for (final c in constraints) {
      final lower = c.toLowerCase().trim();
      if (lower.startsWith('gbnt.autoscaling.cooldown=')) {
        return lower.split('=').last.trim();
      }
    }
    return '60s';
  }
}

class Task {
  final String id;
  final String serviceId;
  final String nodeId;
  final String status;
  final String containerName;
  final String containerIp;
  final String cpuLimit;
  final String memoryLimit;
  final String cpuReservation;
  final String memoryReservation;
  final double cpuPercent;
  final int memUsedBytes;
  final String error;
  final String createdAt;

  Task({
    required this.id,
    required this.serviceId,
    required this.nodeId,
    required this.status,
    this.containerName = '',
    this.containerIp = '',
    this.cpuLimit = '',
    this.memoryLimit = '',
    this.cpuReservation = '',
    this.memoryReservation = '',
    this.cpuPercent = 0.0,
    this.memUsedBytes = 0,
    this.error = '',
    this.createdAt = '',
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'] ?? '',
      serviceId: json['service_id'] ?? '',
      nodeId: json['node_id'] ?? '',
      status: json['status'] ?? '',
      containerName: json['container_name'] ?? '',
      containerIp: json['container_ip'] ?? '',
      cpuLimit: json['cpu_limit'] ?? '',
      memoryLimit: json['memory_limit'] ?? '',
      cpuReservation: json['cpu_reservation'] ?? '',
      memoryReservation: json['memory_reservation'] ?? '',
      cpuPercent: (json['cpu_percent'] as num?)?.toDouble() ?? 0.0,
      memUsedBytes: (json['mem_used_bytes'] as num?)?.toInt() ?? 0,
      error: json['error'] ?? '',
      createdAt: json['created_at'] ?? '',
    );
  }
}

class DnsRecord {
  final String ip;
  final String hostname;

  DnsRecord({
    required this.ip,
    required this.hostname,
  });

  factory DnsRecord.fromJson(Map<String, dynamic> json) {
    return DnsRecord(
      ip: json['ip'] ?? '',
      hostname: json['hostname'] ?? '',
    );
  }
}

class DashboardState {
  final List<Node> nodes;
  final List<StackModel> stacks;
  final List<Service> services;
  final List<Task> tasks;
  final List<DnsRecord> dnsRecords;
  final bool monitorRunning;
  final String caddyStatus;
  final String caddyfile;
  final String version;
  final String clusterDomain;
  final String clusterJoinToken;
  final String activeApiToken;
  final String managerIp;
  final bool updateAvailable;
  final String latestVersion;
  final String releaseNotes;
  final String releaseUrl;
  final String activeSreProfile;
  final UserSession? currentUser;

  DashboardState({
    this.nodes = const [],
    this.stacks = const [],
    this.services = const [],
    this.tasks = const [],
    this.dnsRecords = const [],
    this.monitorRunning = false,
    this.caddyStatus = 'not running',
    this.caddyfile = '',
    this.activeSreProfile = 'cloud-native',
    this.version = 'dev',
    this.clusterDomain = 'gbnt.local',
    this.clusterJoinToken = '',
    this.activeApiToken = '',
    this.managerIp = '',
    this.updateAvailable = false,
    this.latestVersion = '',
    this.releaseNotes = '',
    this.releaseUrl = '',
    this.currentUser,
  });

  factory DashboardState.fromJson(Map<String, dynamic> json) {
    return DashboardState(
      nodes: (json['nodes'] as List? ?? [])
          .map((e) => Node.fromJson(e))
          .toList(),
      stacks: (json['stacks'] as List? ?? [])
          .map((e) => StackModel.fromJson(e))
          .toList(),
      services: (json['services'] as List? ?? [])
          .map((e) => Service.fromJson(e))
          .toList(),
      tasks: (json['tasks'] as List? ?? [])
          .map((e) => Task.fromJson(e))
          .toList(),
      dnsRecords: (json['dns_records'] as List? ?? [])
          .map((e) => DnsRecord.fromJson(e))
          .toList(),
      monitorRunning: json['monitor_running'] ?? false,
      caddyStatus: json['caddy_status'] ?? 'not running',
      caddyfile: json['caddyfile'] ?? '',
      activeSreProfile: json['active_sre_profile'] ?? 'cloud-native',
      version: json['version'] ?? 'dev',
      clusterDomain: json['cluster_domain'] ?? 'gbnt.local',
      clusterJoinToken: json['cluster_join_token'] ?? '',
      activeApiToken: json['active_api_token'] ?? '',
      managerIp: json['manager_ip'] ?? '',
      updateAvailable: json['update_available'] ?? false,
      latestVersion: json['latest_version'] ?? '',
      releaseNotes: json['release_notes'] ?? '',
      releaseUrl: json['release_url'] ?? '',
      currentUser: json['current_user'] != null ? UserSession.fromJson(json['current_user']) : null,
    );
  }
}

class UserPermissions {
  final bool canDeployStacks;
  final bool canDeleteStacks;
  final bool canRestartTasks;
  final bool canDeleteTasks;
  final bool canExecuteShell;
  final bool canManageNodes;
  final bool canManageCaddy;
  final bool canManageCoreDNS;
  final bool canManageSecurity;
  final bool canViewObservability;
  final bool canViewAuditLogs;
  final bool canExportAuditLogs;

  const UserPermissions({
    this.canDeployStacks = true,
    this.canDeleteStacks = true,
    this.canRestartTasks = true,
    this.canDeleteTasks = true,
    this.canExecuteShell = true,
    this.canManageNodes = true,
    this.canManageCaddy = true,
    this.canManageCoreDNS = true,
    this.canManageSecurity = true,
    this.canViewObservability = true,
    this.canViewAuditLogs = true,
    this.canExportAuditLogs = true,
  });

  factory UserPermissions.fromJson(Map<String, dynamic> json) {
    return UserPermissions(
      canDeployStacks: json['can_deploy_stacks'] ?? true,
      canDeleteStacks: json['can_delete_stacks'] ?? true,
      canRestartTasks: json['can_restart_tasks'] ?? true,
      canDeleteTasks: json['can_delete_tasks'] ?? true,
      canExecuteShell: json['can_execute_shell'] ?? true,
      canManageNodes: json['can_manage_nodes'] ?? true,
      canManageCaddy: json['can_manage_caddy'] ?? true,
      canManageCoreDNS: json['can_manage_coredns'] ?? true,
      canManageSecurity: json['can_manage_security'] ?? true,
      canViewObservability: json['can_view_observability'] ?? true,
      canViewAuditLogs: json['can_view_audit_logs'] ?? true,
      canExportAuditLogs: json['can_export_audit_logs'] ?? true,
    );
  }
}

class UserSession {
  final String username;
  final String displayName;
  final String email;
  final String role; // "admin", "operator", "readonly", "auditor"
  final String provider;
  final UserPermissions permissions;

  const UserSession({
    required this.username,
    required this.displayName,
    this.email = '',
    this.role = 'admin',
    this.provider = 'local',
    this.permissions = const UserPermissions(),
  });

  bool get isAdmin => role == 'admin';
  bool get isOperator => role == 'operator';
  bool get isReadOnly => role == 'readonly';
  bool get isAuditor => role == 'auditor';

  factory UserSession.fromJson(Map<String, dynamic> json) {
    return UserSession(
      username: json['username'] ?? '',
      displayName: json['display_name'] ?? json['username'] ?? '',
      email: json['email'] ?? '',
      role: json['role'] ?? 'admin',
      provider: json['provider'] ?? 'local',
      permissions: json['permissions'] != null
          ? UserPermissions.fromJson(json['permissions'])
          : const UserPermissions(),
    );
  }
}

class AuthProvider {
  final String id;
  final String name;
  final String type; // "local", "ldap", "oidc"
  final String providerType; // for oidc: "keycloak", "google", "github", "azure", "okta", "generic"

  const AuthProvider({
    required this.id,
    required this.name,
    required this.type,
    this.providerType = 'generic',
  });

  factory AuthProvider.fromJson(Map<String, dynamic> json) {
    return AuthProvider(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      type: json['type'] ?? 'local',
      providerType: json['provider_type'] ?? 'generic',
    );
  }

  bool get isOIDC => type == 'oidc';
  bool get isLDAP => type == 'ldap';
  bool get isLocal => type == 'local';
}

class LDAPConfig {
  final String id;
  final String name;
  final bool enabled;
  final String host;
  final int port;
  final String security; // "none", "tls", "starttls"
  final bool insecureSkipVerify;
  final String bindDn;
  final String bindPassword;
  final String baseDn;
  final String userFilter;
  final String userAttr;
  final String groupBaseDn;
  final String groupFilter;
  final String adminGroupDn;
  final String operatorGroupDn;
  final String readOnlyGroupDn;
  final String defaultRole;

  LDAPConfig({
    required this.id,
    required this.name,
    this.enabled = true,
    required this.host,
    this.port = 389,
    this.security = 'none',
    this.insecureSkipVerify = false,
    this.bindDn = '',
    this.bindPassword = '',
    required this.baseDn,
    this.userFilter = '(&(objectClass=user)(sAMAccountName=%s))',
    this.userAttr = 'sAMAccountName',
    this.groupBaseDn = '',
    this.groupFilter = '(&(objectClass=group)(member=%s))',
    this.adminGroupDn = '',
    this.operatorGroupDn = '',
    this.readOnlyGroupDn = '',
    this.defaultRole = 'readonly',
  });

  factory LDAPConfig.fromJson(Map<String, dynamic> json) {
    return LDAPConfig(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      enabled: json['enabled'] ?? true,
      host: json['host'] ?? '',
      port: (json['port'] as num?)?.toInt() ?? 389,
      security: json['security'] ?? 'none',
      insecureSkipVerify: json['insecure_skip_verify'] == true,
      bindDn: json['bind_dn'] ?? '',
      bindPassword: json['bind_password'] ?? '',
      baseDn: json['base_dn'] ?? '',
      userFilter: json['user_filter'] ?? '(&(objectClass=user)(sAMAccountName=%s))',
      userAttr: json['user_attr'] ?? 'sAMAccountName',
      groupBaseDn: json['group_base_dn'] ?? '',
      groupFilter: json['group_filter'] ?? '(&(objectClass=group)(member=%s))',
      adminGroupDn: json['admin_group_dn'] ?? '',
      operatorGroupDn: json['operator_group_dn'] ?? '',
      readOnlyGroupDn: json['readonly_group_dn'] ?? '',
      defaultRole: json['default_role'] ?? 'readonly',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'enabled': enabled,
        'host': host,
        'port': port,
        'security': security,
        'insecure_skip_verify': insecureSkipVerify,
        'bind_dn': bindDn,
        'bind_password': bindPassword,
        'base_dn': baseDn,
        'user_filter': userFilter,
        'user_attr': userAttr,
        'group_base_dn': groupBaseDn,
        'group_filter': groupFilter,
        'admin_group_dn': adminGroupDn,
        'operator_group_dn': operatorGroupDn,
        'readonly_group_dn': readOnlyGroupDn,
        'default_role': defaultRole,
      };
}

class LDAPTestResult {
  final bool connected;
  final bool tlsActive;
  final bool bindSuccessful;
  final bool userFound;
  final String message;
  final int latencyMs;
  final String? assignedRole;

  LDAPTestResult({
    required this.connected,
    required this.tlsActive,
    required this.bindSuccessful,
    required this.userFound,
    required this.message,
    required this.latencyMs,
    this.assignedRole,
  });

  factory LDAPTestResult.fromJson(Map<String, dynamic> json) {
    final authRes = json['auth_result'] as Map<String, dynamic>?;
    return LDAPTestResult(
      connected: json['connected'] == true,
      tlsActive: json['tls_active'] == true,
      bindSuccessful: json['bind_successful'] == true,
      userFound: json['user_found'] == true,
      message: json['message'] ?? '',
      latencyMs: (json['latency_ms'] as num?)?.toInt() ?? 0,
      assignedRole: authRes?['role']?.toString(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OIDC / OAuth2 SSO Models
// ─────────────────────────────────────────────────────────────────────────────

class OIDCConfig {
  final String id;
  final String name;
  final String providerType; // generic, keycloak, google, github, azure, okta
  final bool enabled;
  final String issuerUrl;
  final String clientId;
  final String clientSecret;
  final String redirectUri;
  final String scopes;
  final String roleClaimPath;
  final String adminClaim;
  final String operatorClaim;
  final String readonlyClaim;
  final String defaultRole;
  final bool insecureSkipVerify;

  OIDCConfig({
    this.id = '',
    required this.name,
    this.providerType = 'generic',
    this.enabled = true,
    required this.issuerUrl,
    required this.clientId,
    this.clientSecret = '',
    this.redirectUri = '',
    this.scopes = 'openid profile email',
    this.roleClaimPath = 'groups',
    this.adminClaim = '',
    this.operatorClaim = '',
    this.readonlyClaim = '',
    this.defaultRole = 'readonly',
    this.insecureSkipVerify = false,
  });

  factory OIDCConfig.fromJson(Map<String, dynamic> json) {
    return OIDCConfig(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      providerType: json['provider_type'] ?? 'generic',
      enabled: json['enabled'] ?? true,
      issuerUrl: json['issuer_url'] ?? '',
      clientId: json['client_id'] ?? '',
      clientSecret: json['client_secret'] ?? '',
      redirectUri: json['redirect_uri'] ?? '',
      scopes: json['scopes'] ?? 'openid profile email',
      roleClaimPath: json['role_claim_path'] ?? 'groups',
      adminClaim: json['admin_claim'] ?? '',
      operatorClaim: json['operator_claim'] ?? '',
      readonlyClaim: json['readonly_claim'] ?? '',
      defaultRole: json['default_role'] ?? 'readonly',
      insecureSkipVerify: json['insecure_skip_verify'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'provider_type': providerType,
        'enabled': enabled,
        'issuer_url': issuerUrl,
        'client_id': clientId,
        'client_secret': clientSecret,
        'redirect_uri': redirectUri,
        'scopes': scopes,
        'role_claim_path': roleClaimPath,
        'admin_claim': adminClaim,
        'operator_claim': operatorClaim,
        'readonly_claim': readonlyClaim,
        'default_role': defaultRole,
        'insecure_skip_verify': insecureSkipVerify,
      };
}

class OIDCTestResult {
  final bool connected;
  final bool issuerReachable;
  final bool discoveryOk;
  final bool jwksReachable;
  final String authorizationEndpoint;
  final String tokenEndpoint;
  final String jwksUri;
  final int keyCount;
  final String message;
  final int latencyMs;

  OIDCTestResult({
    required this.connected,
    required this.issuerReachable,
    required this.discoveryOk,
    required this.jwksReachable,
    this.authorizationEndpoint = '',
    this.tokenEndpoint = '',
    this.jwksUri = '',
    this.keyCount = 0,
    required this.message,
    this.latencyMs = 0,
  });

  factory OIDCTestResult.fromJson(Map<String, dynamic> json) {
    return OIDCTestResult(
      connected: json['connected'] == true,
      issuerReachable: json['issuer_reachable'] == true,
      discoveryOk: json['discovery_ok'] == true,
      jwksReachable: json['jwks_reachable'] == true,
      authorizationEndpoint: json['authorization_endpoint'] ?? '',
      tokenEndpoint: json['token_endpoint'] ?? '',
      jwksUri: json['jwks_uri'] ?? '',
      keyCount: (json['key_count'] as num?)?.toInt() ?? 0,
      message: json['message'] ?? '',
      latencyMs: (json['latency_ms'] as num?)?.toInt() ?? 0,
    );
  }
}

class OIDCProviderPreset {
  final String type;
  final String name;
  final String issuerUrl;
  final String scopes;
  final String roleClaimPath;
  final String description;
  final String docsUrl;

  OIDCProviderPreset({
    required this.type,
    required this.name,
    required this.issuerUrl,
    required this.scopes,
    required this.roleClaimPath,
    required this.description,
    required this.docsUrl,
  });

  factory OIDCProviderPreset.fromJson(Map<String, dynamic> json) {
    return OIDCProviderPreset(
      type: json['type'] ?? 'generic',
      name: json['name'] ?? '',
      issuerUrl: json['issuer_url'] ?? '',
      scopes: json['scopes'] ?? 'openid profile email',
      roleClaimPath: json['role_claim_path'] ?? 'groups',
      description: json['description'] ?? '',
      docsUrl: json['docs_url'] ?? '',
    );
  }
}


class SLOItem {
  final String serviceId;
  final String serviceName;
  final String stackId;
  final double target;
  final String window;
  final String template;
  final String journey;
  final String errorQuery;
  final String totalQuery;
  final double errorBudgetRemaining;
  final double burnRate;
  final String status;
  final String indicator;
  final String latencyThreshold;

  SLOItem({
    required this.serviceId,
    required this.serviceName,
    required this.stackId,
    required this.target,
    required this.window,
    this.indicator = 'ratio',
    this.latencyThreshold = '',
    this.template = '',
    this.journey = '',
    required this.errorQuery,
    required this.totalQuery,
    required this.errorBudgetRemaining,
    required this.burnRate,
    required this.status,
  });

  factory SLOItem.fromJson(Map<String, dynamic> json) {
    return SLOItem(
      serviceId: json['service_id'] ?? '',
      serviceName: json['service_name'] ?? '',
      stackId: json['stack_id'] ?? '',
      target: (json['target'] as num?)?.toDouble() ?? 99.9,
      window: json['window'] ?? '30d',
      indicator: json['indicator'] ?? 'ratio',
      latencyThreshold: json['latency_threshold'] ?? '',
      template: json['template'] ?? '',
      journey: json['journey'] ?? '',
      errorQuery: json['error_query'] ?? '',
      totalQuery: json['total_query'] ?? '',
      errorBudgetRemaining: (json['error_budget_remaining'] as num?)?.toDouble() ?? 100.0,
      burnRate: (json['burn_rate'] as num?)?.toDouble() ?? 0.0,
      status: json['status'] ?? 'healthy',
    );
  }
}

class UserJourney {
  final String name;
  final List<SLOItem> services;
  final double compositeTarget;
  final double avgErrorBudget;
  final String bottleneckService;
  final double bottleneckBudget;
  final String status;

  UserJourney({
    required this.name,
    required this.services,
    required this.compositeTarget,
    required this.avgErrorBudget,
    required this.bottleneckService,
    required this.bottleneckBudget,
    required this.status,
  });

  factory UserJourney.fromJson(Map<String, dynamic> json) {
    return UserJourney(
      name: json['name'] ?? '',
      services: (json['services'] as List? ?? []).map((e) => SLOItem.fromJson(e)).toList(),
      compositeTarget: (json['composite_target'] as num?)?.toDouble() ?? 99.9,
      avgErrorBudget: (json['avg_error_budget'] as num?)?.toDouble() ?? 100.0,
      bottleneckService: json['bottleneck_service'] ?? '',
      bottleneckBudget: (json['bottleneck_budget'] as num?)?.toDouble() ?? 100.0,
      status: json['status'] ?? 'healthy',
    );
  }
}

class SLOCorrelationEvent {
  final String timestamp;
  final String type;
  final String stackName;
  final String serviceName;
  final String description;
  final double burnRate;

  SLOCorrelationEvent({
    required this.timestamp,
    required this.type,
    required this.stackName,
    required this.serviceName,
    required this.description,
    required this.burnRate,
  });

  factory SLOCorrelationEvent.fromJson(Map<String, dynamic> json) {
    return SLOCorrelationEvent(
      timestamp: json['timestamp'] ?? '',
      type: json['type'] ?? 'deployment',
      stackName: json['stack_name'] ?? '',
      serviceName: json['service_name'] ?? '',
      description: json['description'] ?? '',
      burnRate: (json['burn_rate'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class SLOValidationItem {
  final String serviceName;
  final bool valid;
  final double target;
  final String window;
  final String template;
  final String errorQuery;
  final String totalQuery;
  final String error;
  final String backtestStatus;
  final String backtestDetails;

  SLOValidationItem({
    required this.serviceName,
    required this.valid,
    required this.target,
    required this.window,
    required this.template,
    required this.errorQuery,
    required this.totalQuery,
    this.error = '',
    required this.backtestStatus,
    required this.backtestDetails,
  });

  factory SLOValidationItem.fromJson(Map<String, dynamic> json) {
    return SLOValidationItem(
      serviceName: json['service_name'] ?? '',
      valid: json['valid'] ?? false,
      target: (json['target'] as num?)?.toDouble() ?? 99.9,
      window: json['window'] ?? '30d',
      template: json['template'] ?? '',
      errorQuery: json['error_query'] ?? '',
      totalQuery: json['total_query'] ?? '',
      error: json['error'] ?? '',
      backtestStatus: json['backtest_status'] ?? 'passed',
      backtestDetails: json['backtest_details'] ?? '',
    );
  }
}

class SLOHistoryPoint {
  final String timestamp;
  final double budgetRemaining;
  final double burnRate;

  SLOHistoryPoint({
    required this.timestamp,
    required this.budgetRemaining,
    required this.burnRate,
  });

  factory SLOHistoryPoint.fromJson(Map<String, dynamic> json) {
    return SLOHistoryPoint(
      timestamp: json['timestamp'] ?? '',
      budgetRemaining: (json['budget_remaining'] as num?)?.toDouble() ?? 100.0,
      burnRate: (json['burn_rate'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class SLOREDMetrics {
  final double rps;
  final double errorRps;
  final double p99LatencyMs;

  SLOREDMetrics({
    required this.rps,
    required this.errorRps,
    required this.p99LatencyMs,
  });

  factory SLOREDMetrics.fromJson(Map<String, dynamic> json) {
    return SLOREDMetrics(
      rps: (json['rps'] as num?)?.toDouble() ?? 0.0,
      errorRps: (json['error_rps'] as num?)?.toDouble() ?? 0.0,
      p99LatencyMs: (json['p99_latency_ms'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class CustomDNSRecord {
  final String id;
  final String domain;
  final String ip;
  final String recordType;
  final int ttl;
  final String createdAt;

  CustomDNSRecord({
    required this.id,
    required this.domain,
    required this.ip,
    required this.recordType,
    required this.ttl,
    required this.createdAt,
  });

  factory CustomDNSRecord.fromJson(Map<String, dynamic> json) {
    return CustomDNSRecord(
      id: json['id'] ?? '',
      domain: json['domain'] ?? '',
      ip: json['ip'] ?? '',
      recordType: json['record_type'] ?? 'A',
      ttl: (json['ttl'] as num?)?.toInt() ?? 60,
      createdAt: json['created_at'] ?? '',
    );
  }
}

class DNSDigAnswer {
  final String name;
  final String type;
  final int ttl;
  final String data;

  DNSDigAnswer({
    required this.name,
    required this.type,
    required this.ttl,
    required this.data,
  });

  factory DNSDigAnswer.fromJson(Map<String, dynamic> json) {
    return DNSDigAnswer(
      name: json['name'] ?? '',
      type: json['type'] ?? '',
      ttl: (json['ttl'] as num?)?.toInt() ?? 60,
      data: json['data'] ?? '',
    );
  }
}

class DNSDigResult {
  final String domain;
  final String recordType;
  final String status;
  final double queryTimeMs;
  final String server;
  final List<DNSDigAnswer> answers;
  final String rawOutput;

  DNSDigResult({
    required this.domain,
    required this.recordType,
    required this.status,
    required this.queryTimeMs,
    required this.server,
    required this.answers,
    required this.rawOutput,
  });

  factory DNSDigResult.fromJson(Map<String, dynamic> json) {
    return DNSDigResult(
      domain: json['domain'] ?? '',
      recordType: json['record_type'] ?? 'A',
      status: json['status'] ?? '',
      queryTimeMs: (json['query_time_ms'] as num?)?.toDouble() ?? 0.0,
      server: json['server'] ?? '',
      answers: (json['answers'] as List? ?? []).map((e) => DNSDigAnswer.fromJson(e)).toList(),
      rawOutput: json['raw_output'] ?? '',
    );
  }
}

class CoreDNSStatusInfo {
  final String status;
  final int uptimeSeconds;
  final int memBytes;
  final int listeningPort;
  final List<String> forwarders;
  final int totalRecords;

  CoreDNSStatusInfo({
    required this.status,
    required this.uptimeSeconds,
    required this.memBytes,
    required this.listeningPort,
    required this.forwarders,
    required this.totalRecords,
  });

  factory CoreDNSStatusInfo.fromJson(Map<String, dynamic> json) {
    return CoreDNSStatusInfo(
      status: json['status'] ?? 'stopped',
      uptimeSeconds: (json['uptime_seconds'] as num?)?.toInt() ?? 0,
      memBytes: (json['mem_bytes'] as num?)?.toInt() ?? 0,
      listeningPort: (json['listening_port'] as num?)?.toInt() ?? 5354,
      forwarders: (json['forwarders'] as List? ?? []).map((e) => e.toString()).toList(),
      totalRecords: (json['total_records'] as num?)?.toInt() ?? 0,
    );
  }
}


class LocalUser {
  final String id;
  final String username;
  final String displayName;
  final String email;
  final String role;
  final bool enabled;
  final bool mfaEnabled;
  final String? lastLogin;
  final String createdAt;
  final String updatedAt;

  LocalUser({
    required this.id,
    required this.username,
    required this.displayName,
    required this.email,
    required this.role,
    required this.enabled,
    this.mfaEnabled = false,
    this.lastLogin,
    required this.createdAt,
    required this.updatedAt,
  });

  factory LocalUser.fromJson(Map<String, dynamic> json) {
    return LocalUser(
      id: json["id"] ?? "",
      username: json["username"] ?? "",
      displayName: json["display_name"] ?? "",
      email: json["email"] ?? "",
      role: json["role"] ?? "readonly",
      enabled: json["enabled"] ?? true,
      mfaEnabled: json["mfa_enabled"] == true,
      lastLogin: json["last_login"],
      createdAt: json["created_at"] ?? "",
      updatedAt: json["updated_at"] ?? "",
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "id": id,
      "username": username,
      "display_name": displayName,
      "email": email,
      "role": role,
      "enabled": enabled,
      "mfa_enabled": mfaEnabled,
    };
  }
}

class AuditLog {
  final String id;
  final String timestamp;
  final String username;
  final String provider;
  final String ipAddress;
  final String action;
  final String status;
  final String details;
  final String prevHash;
  final String hash;

  AuditLog({
    required this.id,
    required this.timestamp,
    required this.username,
    required this.provider,
    required this.ipAddress,
    required this.action,
    required this.status,
    required this.details,
    this.prevHash = "",
    this.hash = "",
  });

  factory AuditLog.fromJson(Map<String, dynamic> json) {
    return AuditLog(
      id: json["id"] ?? "",
      timestamp: json["timestamp"] ?? "",
      username: json["username"] ?? "",
      provider: json["provider"] ?? "LOCAL",
      ipAddress: json["ip_address"] ?? "",
      action: json["action"] ?? "",
      status: json["status"] ?? "SUCCESS",
      details: json["details"] ?? "",
      prevHash: json["prev_hash"] ?? "",
      hash: json["hash"] ?? "",
    );
  }
}

class SIEMConfig {
  final bool mfaEnforced;
  final bool siemEnabled;
  final String siemHost;
  final int siemPort;
  final String siemProtocol;
  final String siemFormat;
  final String updatedAt;

  SIEMConfig({
    this.mfaEnforced = false,
    this.siemEnabled = false,
    this.siemHost = '',
    this.siemPort = 514,
    this.siemProtocol = 'UDP',
    this.siemFormat = 'RFC5424',
    this.updatedAt = '',
  });

  factory SIEMConfig.fromJson(Map<String, dynamic> json) {
    return SIEMConfig(
      mfaEnforced: json['mfa_enforced'] == true,
      siemEnabled: json['siem_enabled'] == true,
      siemHost: json['siem_host'] ?? '',
      siemPort: (json['siem_port'] as num?)?.toInt() ?? 514,
      siemProtocol: json['siem_protocol'] ?? 'UDP',
      siemFormat: json['siem_format'] ?? 'RFC5424',
      updatedAt: json['updated_at'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'mfa_enforced': mfaEnforced,
      'siem_enabled': siemEnabled,
      'siem_host': siemHost,
      'siem_port': siemPort,
      'siem_protocol': siemProtocol,
      'siem_format': siemFormat,
    };
  }
}

class AuditVerificationResult {
  final bool valid;
  final int totalRecords;
  final int verifiedRecords;
  final String lastHash;
  final String error;

  AuditVerificationResult({
    required this.valid,
    required this.totalRecords,
    required this.verifiedRecords,
    required this.lastHash,
    this.error = '',
  });

  factory AuditVerificationResult.fromJson(Map<String, dynamic> json) {
    return AuditVerificationResult(
      valid: json['valid'] == true,
      totalRecords: (json['total_records'] as num?)?.toInt() ?? 0,
      verifiedRecords: (json['verified_records'] as num?)?.toInt() ?? 0,
      lastHash: json['last_hash'] ?? '',
      error: json['error'] ?? '',
    );
  }
}

class LokiLogEntry {
  final String timestamp;
  final String timestampNs;
  final String container;
  final String node;
  final String stack;
  final String stream;
  final String level;
  final String message;
  final Map<String, String> labels;

  LokiLogEntry({
    required this.timestamp,
    required this.timestampNs,
    required this.container,
    required this.node,
    required this.stack,
    required this.stream,
    required this.level,
    required this.message,
    this.labels = const {},
  });

  factory LokiLogEntry.fromJson(Map<String, dynamic> json) {
    Map<String, String> labelsMap = {};
    if (json['labels'] != null && json['labels'] is Map) {
      (json['labels'] as Map).forEach((k, v) {
        labelsMap[k.toString()] = v.toString();
      });
    }

    return LokiLogEntry(
      timestamp: json['timestamp']?.toString() ?? '',
      timestampNs: json['timestamp_ns']?.toString() ?? '',
      container: json['container']?.toString() ?? '',
      node: json['node']?.toString() ?? 'manager',
      stack: json['stack']?.toString() ?? '',
      stream: json['stream']?.toString() ?? 'stdout',
      level: json['level']?.toString() ?? 'INFO',
      message: json['message']?.toString() ?? '',
      labels: labelsMap,
    );
  }
}

class LokiLabelsResponse {
  final List<String> containers;
  final List<String> nodes;
  final List<String> stacks;
  final List<String> streams;
  final List<String> levels;

  LokiLabelsResponse({
    required this.containers,
    required this.nodes,
    required this.stacks,
    required this.streams,
    required this.levels,
  });

  factory LokiLabelsResponse.fromJson(Map<String, dynamic> json) {
    List<String> parseList(dynamic raw) {
      if (raw == null || raw is! List) return [];
      return raw.map((e) => e.toString()).toList();
    }

    List<String> nodeNames = [];
    if (json['nodes'] != null && json['nodes'] is List) {
      for (var item in json['nodes']) {
        if (item is Map && item['name'] != null) {
          nodeNames.add(item['name'].toString());
        } else if (item is Map && item['id'] != null) {
          nodeNames.add(item['id'].toString());
        } else {
          nodeNames.add(item.toString());
        }
      }
    }

    List<String> stackNames = [];
    if (json['stacks'] != null && json['stacks'] is List) {
      for (var item in json['stacks']) {
        if (item is Map && item['name'] != null) {
          stackNames.add(item['name'].toString());
        } else {
          stackNames.add(item.toString());
        }
      }
    }

    return LokiLabelsResponse(
      containers: parseList(json['containers']),
      nodes: nodeNames,
      stacks: stackNames,
      streams: parseList(json['streams']),
      levels: parseList(json['levels']),
    );
  }
}

// ── Storage & Backups Models ──────────────────────────────────────

class StorageVolumeModel {
  final String id;
  final String name;
  final String type; // "shared_pool", "docker_named", "host_bind"
  final String driver;
  final String sourcePath;
  final String targetPath;
  final String stackId;
  final String stackName;
  final String serviceName;
  final String nodeId;
  final String nodeIp;
  final String nodeHostname;
  final String nodeRole;
  final int sizeBytes;
  final String sizeFormatted;
  final bool isShared;
  final String lastScannedAt;

  StorageVolumeModel({
    required this.id,
    required this.name,
    required this.type,
    this.driver = 'local',
    required this.sourcePath,
    required this.targetPath,
    this.stackId = '',
    this.stackName = '',
    this.serviceName = '',
    this.nodeId = 'cluster',
    this.nodeIp = '',
    this.nodeHostname = '',
    this.nodeRole = '',
    this.sizeBytes = 0,
    this.sizeFormatted = '0 B',
    this.isShared = false,
    this.lastScannedAt = '',
  });

  factory StorageVolumeModel.fromJson(Map<String, dynamic> json) {
    return StorageVolumeModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      type: json['type'] ?? 'host_bind',
      driver: json['driver'] ?? 'local',
      sourcePath: json['source_path'] ?? '',
      targetPath: json['target_path'] ?? '',
      stackId: json['stack_id'] ?? '',
      stackName: json['stack_name'] ?? '',
      serviceName: json['service_name'] ?? '',
      nodeId: json['node_id'] ?? 'cluster',
      nodeIp: json['node_ip'] ?? '',
      nodeHostname: json['node_hostname'] ?? '',
      nodeRole: json['node_role'] ?? '',
      sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
      sizeFormatted: json['size_formatted'] ?? '0 B',
      isShared: json['is_shared'] == true,
      lastScannedAt: json['last_scanned_at'] ?? '',
    );
  }
}

class DirectoryEntryModel {
  final String name;
  final String path;
  final bool isDir;
  final int sizeBytes;
  final String sizeFormatted;
  final String permissions;
  final String modTime;
  final String nodeId;

  DirectoryEntryModel({
    required this.name,
    required this.path,
    required this.isDir,
    this.sizeBytes = 0,
    this.sizeFormatted = '0 B',
    this.permissions = '',
    this.modTime = '',
    this.nodeId = '',
  });

  factory DirectoryEntryModel.fromJson(Map<String, dynamic> json) {
    return DirectoryEntryModel(
      name: json['name'] ?? '',
      path: json['path'] ?? '',
      isDir: json['is_dir'] == true,
      sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
      sizeFormatted: json['size_formatted'] ?? '0 B',
      permissions: json['permissions'] ?? '',
      modTime: json['mod_time'] ?? '',
      nodeId: json['node_id'] ?? '',
    );
  }
}

class BackupModel {
  final String id;
  final String name;
  final String stackId;
  final String stackName;
  final String volumeName;
  final String sourcePath;
  final String filePath;
  final int sizeBytes;
  final String sizeFormatted;
  final String sha256;
  final String status;
  final bool isScheduled;
  final String scheduleId;
  final String createdAt;

  BackupModel({
    required this.id,
    required this.name,
    this.stackId = '',
    this.stackName = '',
    this.volumeName = '',
    this.sourcePath = '',
    this.filePath = '',
    this.sizeBytes = 0,
    this.sizeFormatted = '0 B',
    this.sha256 = '',
    this.status = 'completed',
    this.isScheduled = false,
    this.scheduleId = '',
    this.createdAt = '',
  });

  factory BackupModel.fromJson(Map<String, dynamic> json) {
    return BackupModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      stackId: json['stack_id'] ?? '',
      stackName: json['stack_name'] ?? '',
      volumeName: json['volume_name'] ?? '',
      sourcePath: json['source_path'] ?? '',
      filePath: json['file_path'] ?? '',
      sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
      sizeFormatted: json['size_formatted'] ?? '0 B',
      sha256: json['sha256'] ?? '',
      status: json['status'] ?? 'completed',
      isScheduled: json['is_scheduled'] == true,
      scheduleId: json['schedule_id'] ?? '',
      createdAt: json['created_at'] ?? '',
    );
  }
}

class BackupScheduleModel {
  final String id;
  final String name;
  final String cronExpression;
  final String targetType;
  final String targetId;
  final String targetName;
  final String destinationPath;
  final int retentionCount;
  final bool pauseContainers;
  final bool enabled;
  final String? lastRunAt;
  final String createdAt;

  BackupScheduleModel({
    required this.id,
    required this.name,
    required this.cronExpression,
    this.targetType = 'stack',
    this.targetId = '',
    this.targetName = '',
    this.destinationPath = '',
    this.retentionCount = 7,
    this.pauseContainers = true,
    this.enabled = true,
    this.lastRunAt,
    this.createdAt = '',
  });

  factory BackupScheduleModel.fromJson(Map<String, dynamic> json) {
    return BackupScheduleModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      cronExpression: json['cron_expression'] ?? '0 3 * * *',
      targetType: json['target_type'] ?? 'stack',
      targetId: json['target_id'] ?? '',
      targetName: json['target_name'] ?? '',
      destinationPath: json['destination_path'] ?? '',
      retentionCount: (json['retention_count'] as num?)?.toInt() ?? 7,
      pauseContainers: json['pause_containers'] != false,
      enabled: json['enabled'] != false,
      lastRunAt: json['last_run_at'],
      createdAt: json['created_at'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'cron_expression': cronExpression,
      'target_type': targetType,
      'target_id': targetId,
      'target_name': targetName,
      'destination_path': destinationPath,
      'retention_count': retentionCount,
      'pause_containers': pauseContainers,
      'enabled': enabled,
    };
  }
}

class NodePoolHealthModel {
  final String nodeId;
  final String nodeIp;
  final String role;
  final String status;
  final String path;
  final bool isMounted;
  final bool isWritable;
  final int totalBytes;
  final int usedBytes;
  final int freeBytes;
  final double usagePercent;
  final String? error;

  NodePoolHealthModel({
    required this.nodeId,
    required this.nodeIp,
    required this.role,
    required this.status,
    required this.path,
    this.isMounted = false,
    this.isWritable = false,
    this.totalBytes = 0,
    this.usedBytes = 0,
    this.freeBytes = 0,
    this.usagePercent = 0.0,
    this.error,
  });

  factory NodePoolHealthModel.fromJson(Map<String, dynamic> json) {
    return NodePoolHealthModel(
      nodeId: json['node_id'] ?? '',
      nodeIp: json['node_ip'] ?? '',
      role: json['role'] ?? '',
      status: json['status'] ?? 'unknown',
      path: json['path'] ?? '',
      isMounted: json['is_mounted'] == true,
      isWritable: json['is_writable'] == true,
      totalBytes: (json['total_bytes'] as num?)?.toInt() ?? 0,
      usedBytes: (json['used_bytes'] as num?)?.toInt() ?? 0,
      freeBytes: (json['free_bytes'] as num?)?.toInt() ?? 0,
      usagePercent: (json['usage_percent'] as num?)?.toDouble() ?? 0.0,
      error: json['error'],
    );
  }
}

class PoolHealthModel {
  final String poolPath;
  final String status;
  final int totalBytes;
  final int usedBytes;
  final int freeBytes;
  final double usagePercent;
  final String totalFormatted;
  final String usedFormatted;
  final String freeFormatted;
  final List<NodePoolHealthModel> nodes;

  PoolHealthModel({
    required this.poolPath,
    required this.status,
    this.totalBytes = 0,
    this.usedBytes = 0,
    this.freeBytes = 0,
    this.usagePercent = 0.0,
    this.totalFormatted = '0 B',
    this.usedFormatted = '0 B',
    this.freeFormatted = '0 B',
    this.nodes = const [],
  });

  factory PoolHealthModel.fromJson(Map<String, dynamic> json) {
    return PoolHealthModel(
      poolPath: json['pool_path'] ?? '/var/contenedores',
      status: json['status'] ?? 'unknown',
      totalBytes: (json['total_bytes'] as num?)?.toInt() ?? 0,
      usedBytes: (json['used_bytes'] as num?)?.toInt() ?? 0,
      freeBytes: (json['free_bytes'] as num?)?.toInt() ?? 0,
      usagePercent: (json['usage_percent'] as num?)?.toDouble() ?? 0.0,
      totalFormatted: json['total_formatted'] ?? '0 B',
      usedFormatted: json['used_formatted'] ?? '0 B',
      freeFormatted: json['free_formatted'] ?? '0 B',
      nodes: (json['nodes'] as List<dynamic>?)
              ?.map((e) => NodePoolHealthModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}

class StorageMountModel {
  final String id;
  final String name;
  final String device;
  final String mountPoint;
  final String fsType;
  final String options;
  final int dump;
  final int pass;
  final String targetNode;
  final String? credentialsFile;
  final bool autoMount;
  final String status;
  final bool isActive;
  final String? errorMessage;
  final String description;
  final String createdAt;
  final String updatedAt;

  StorageMountModel({
    required this.id,
    required this.name,
    required this.device,
    required this.mountPoint,
    required this.fsType,
    this.options = '',
    this.dump = 0,
    this.pass = 0,
    this.targetNode = 'all',
    this.credentialsFile,
    this.autoMount = true,
    this.status = 'unmounted',
    this.isActive = true,
    this.errorMessage,
    this.description = '',
    this.createdAt = '',
    this.updatedAt = '',
  });

  factory StorageMountModel.fromJson(Map<String, dynamic> json) {
    return StorageMountModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      device: json['device'] ?? '',
      mountPoint: json['mount_point'] ?? '',
      fsType: json['fs_type'] ?? 'nfs',
      options: json['options'] ?? '',
      dump: (json['dump'] as num?)?.toInt() ?? 0,
      pass: (json['pass'] as num?)?.toInt() ?? 0,
      targetNode: json['target_node'] ?? 'all',
      credentialsFile: json['credentials_file'],
      autoMount: json['auto_mount'] != false,
      status: json['status'] ?? 'unmounted',
      isActive: json['is_active'] != false,
      errorMessage: json['error_message'],
      description: json['description'] ?? '',
      createdAt: json['created_at'] ?? '',
      updatedAt: json['updated_at'] ?? '',
    );
  }

  factory StorageMountModel.empty() {
    return StorageMountModel(
      id: '',
      name: '',
      device: '',
      mountPoint: '',
      fsType: '',
    );
  }
}

class TestMountResultModel {
  final bool success;
  final int latencyMs;
  final bool isWritable;
  final int totalBytes;
  final int freeBytes;
  final String? errorMessage;
  final String? output;

  TestMountResultModel({
    required this.success,
    this.latencyMs = 0,
    this.isWritable = false,
    this.totalBytes = 0,
    this.freeBytes = 0,
    this.errorMessage,
    this.output,
  });

  factory TestMountResultModel.fromJson(Map<String, dynamic> json) {
    return TestMountResultModel(
      success: json['success'] == true,
      latencyMs: (json['latency_ms'] as num?)?.toInt() ?? 0,
      isWritable: json['is_writable'] == true,
      totalBytes: (json['total_bytes'] as num?)?.toInt() ?? 0,
      freeBytes: (json['free_bytes'] as num?)?.toInt() ?? 0,
      errorMessage: json['error_message'],
      output: json['output'],
    );
  }
}

// ── Image Security & SBOM Models ─────────────────────────────────────────────

class ImageScanModel {
  final String id;
  final String imageName;
  final String imageDigest;
  final String scannedAt;
  final int criticalCount;
  final int highCount;
  final int mediumCount;
  final int lowCount;
  final int totalCount;
  final String signatureStatus;
  final String? signatureSigner;
  final List<String> hosts;
  final List<String> services;
  final bool inUse;

  ImageScanModel({
    required this.id,
    required this.imageName,
    this.imageDigest = '',
    required this.scannedAt,
    this.criticalCount = 0,
    this.highCount = 0,
    this.mediumCount = 0,
    this.lowCount = 0,
    this.totalCount = 0,
    this.signatureStatus = 'unsigned',
    this.signatureSigner,
    this.hosts = const [],
    this.services = const [],
    this.inUse = true,
  });

  factory ImageScanModel.fromJson(Map<String, dynamic> json) {
    return ImageScanModel(
      id: json['id'] ?? '',
      imageName: json['image_name'] ?? '',
      imageDigest: json['image_digest'] ?? '',
      scannedAt: json['scanned_at'] != null ? json['scanned_at'].toString().split('T')[0] : '',
      criticalCount: (json['critical_count'] as num?)?.toInt() ?? 0,
      highCount: (json['high_count'] as num?)?.toInt() ?? 0,
      mediumCount: (json['medium_count'] as num?)?.toInt() ?? 0,
      lowCount: (json['low_count'] as num?)?.toInt() ?? 0,
      totalCount: (json['total_count'] as num?)?.toInt() ?? 0,
      signatureStatus: json['signature_status'] ?? 'unsigned',
      signatureSigner: json['signature_signer'],
      hosts: (json['hosts'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      services: (json['services'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      inUse: json['in_use'] ?? true,
    );
  }
}

class ImageVulnerabilityModel {
  final String id;
  final String scanId;
  final String cveId;
  final String packageName;
  final String installedVersion;
  final String? fixedVersion;
  final String severity;
  final double cvssScore;
  final String title;
  final String description;
  final String primaryUrl;

  ImageVulnerabilityModel({
    required this.id,
    required this.scanId,
    required this.cveId,
    required this.packageName,
    required this.installedVersion,
    this.fixedVersion,
    required this.severity,
    this.cvssScore = 0.0,
    this.title = '',
    this.description = '',
    this.primaryUrl = '',
  });

  factory ImageVulnerabilityModel.fromJson(Map<String, dynamic> json) {
    return ImageVulnerabilityModel(
      id: json['id'] ?? '',
      scanId: json['scan_id'] ?? '',
      cveId: json['cve_id'] ?? '',
      packageName: json['package_name'] ?? '',
      installedVersion: json['installed_version'] ?? '',
      fixedVersion: json['fixed_version'],
      severity: json['severity'] ?? 'LOW',
      cvssScore: (json['cvss_score'] as num?)?.toDouble() ?? 0.0,
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      primaryUrl: json['primary_url'] ?? '',
    );
  }
}

class TrustedKeyModel {
  final String id;
  final String name;
  final String publicKeyPem;
  final String keyType;
  final bool isDefault;
  final bool hasPrivateKey;
  final String createdAt;

  TrustedKeyModel({
    required this.id,
    required this.name,
    required this.publicKeyPem,
    this.keyType = 'cosign-ecdsa',
    this.isDefault = false,
    this.hasPrivateKey = false,
    required this.createdAt,
  });

  factory TrustedKeyModel.fromJson(Map<String, dynamic> json) {
    return TrustedKeyModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      publicKeyPem: json['public_key_pem'] ?? '',
      keyType: json['key_type'] ?? 'cosign-ecdsa',
      isDefault: json['is_default'] ?? false,
      hasPrivateKey: json['has_private_key'] == true,
      createdAt: json['created_at'] != null ? json['created_at'].toString().split('T')[0] : '',
    );
  }
}

class SecurityPolicyModel {
  final String id;
  final String name;
  final String enforceSignatures;
  final String blockCveSeverity;
  final bool allowUnfixedCve;
  final String trustedRegistries;
  final String updatedAt;

  SecurityPolicyModel({
    required this.id,
    required this.name,
    this.enforceSignatures = 'audit',
    this.blockCveSeverity = 'none',
    this.allowUnfixedCve = true,
    this.trustedRegistries = '["docker.io","ghcr.io","quay.io"]',
    required this.updatedAt,
  });

  factory SecurityPolicyModel.fromJson(Map<String, dynamic> json) {
    return SecurityPolicyModel(
      id: json['id'] ?? 'default',
      name: json['name'] ?? 'Cluster Security Policy',
      enforceSignatures: json['enforce_signatures'] ?? 'audit',
      blockCveSeverity: json['block_cve_severity'] ?? 'none',
      allowUnfixedCve: json['allow_unfixed_cve'] ?? true,
      trustedRegistries: json['trusted_registries'] ?? '["docker.io","ghcr.io","quay.io"]',
      updatedAt: json['updated_at'] != null ? json['updated_at'].toString().split('T')[0] : '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'enforce_signatures': enforceSignatures,
        'block_cve_severity': blockCveSeverity,
        'allow_unfixed_cve': allowUnfixedCve,
        'trusted_registries': trustedRegistries,
      };
}

class SecuritySummaryModel {
  final int totalImages;
  final int totalScanned;
  final int criticalCount;
  final int highCount;
  final int mediumCount;
  final int lowCount;
  final int verifiedSigned;
  final int unsignedCount;

  SecuritySummaryModel({
    this.totalImages = 0,
    this.totalScanned = 0,
    this.criticalCount = 0,
    this.highCount = 0,
    this.mediumCount = 0,
    this.lowCount = 0,
    this.verifiedSigned = 0,
    this.unsignedCount = 0,
  });

  factory SecuritySummaryModel.fromJson(Map<String, dynamic> json) {
    return SecuritySummaryModel(
      totalImages: (json['total_images'] as num?)?.toInt() ?? 0,
      totalScanned: (json['total_scanned'] as num?)?.toInt() ?? 0,
      criticalCount: (json['critical_count'] as num?)?.toInt() ?? 0,
      highCount: (json['high_count'] as num?)?.toInt() ?? 0,
      mediumCount: (json['medium_count'] as num?)?.toInt() ?? 0,
      lowCount: (json['low_count'] as num?)?.toInt() ?? 0,
      verifiedSigned: (json['verified_signed'] as num?)?.toInt() ?? 0,
      unsignedCount: (json['unsigned_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class AdoptionStatsModel {
  final int totalDownloads;
  final Map<String, int> downloadsByOs;
  final int totalReleases;
  final String latestReleaseTag;
  final String latestReleaseDate;
  final int githubStars;
  final int githubForks;
  final int githubWatchers;
  final int githubOpenIssues;
  final List<ReleaseStatsModel> recentReleases;
  final String dataSource;
  final String privacyPolicy;
  final bool telemetryEnabled;
  final String documentationUrl;
  final String checkedAt;

  AdoptionStatsModel({
    this.totalDownloads = 0,
    this.downloadsByOs = const {},
    this.totalReleases = 0,
    this.latestReleaseTag = '',
    this.latestReleaseDate = '',
    this.githubStars = 0,
    this.githubForks = 0,
    this.githubWatchers = 0,
    this.githubOpenIssues = 0,
    this.recentReleases = const [],
    this.dataSource = '',
    this.privacyPolicy = '',
    this.telemetryEnabled = true,
    this.documentationUrl = '',
    this.checkedAt = '',
  });

  factory AdoptionStatsModel.fromJson(Map<String, dynamic> json) {
    Map<String, int> osMap = {};
    if (json['downloads_by_os'] is Map) {
      json['downloads_by_os'].forEach((k, v) {
        osMap[k.toString()] = (v as num?)?.toInt() ?? 0;
      });
    }

    List<ReleaseStatsModel> releases = [];
    if (json['recent_releases'] is List) {
      releases = (json['recent_releases'] as List)
          .map((r) => ReleaseStatsModel.fromJson(r as Map<String, dynamic>))
          .toList();
    }

    return AdoptionStatsModel(
      totalDownloads: (json['total_downloads'] as num?)?.toInt() ?? 0,
      downloadsByOs: osMap,
      totalReleases: (json['total_releases'] as num?)?.toInt() ?? 0,
      latestReleaseTag: json['latest_release_tag'] ?? '',
      latestReleaseDate: json['latest_release_date'] ?? '',
      githubStars: (json['github_stars'] as num?)?.toInt() ?? 0,
      githubForks: (json['github_forks'] as num?)?.toInt() ?? 0,
      githubWatchers: (json['github_watchers'] as num?)?.toInt() ?? 0,
      githubOpenIssues: (json['github_open_issues'] as num?)?.toInt() ?? 0,
      recentReleases: releases,
      dataSource: json['data_source'] ?? '',
      privacyPolicy: json['privacy_policy'] ?? '',
      telemetryEnabled: json['telemetry_enabled'] != false,
      documentationUrl: json['documentation_url'] ?? '',
      checkedAt: json['checked_at'] ?? '',
    );
  }
}

class ReleaseStatsModel {
  final String tagName;
  final String publishedAt;
  final int downloads;
  final String htmlUrl;

  ReleaseStatsModel({
    required this.tagName,
    this.publishedAt = '',
    this.downloads = 0,
    this.htmlUrl = '',
  });

  factory ReleaseStatsModel.fromJson(Map<String, dynamic> json) {
    return ReleaseStatsModel(
      tagName: json['tag_name'] ?? '',
      publishedAt: json['published_at'] ?? '',
      downloads: (json['downloads'] as num?)?.toInt() ?? 0,
      htmlUrl: json['html_url'] ?? '',
    );
  }
}

class GlusterPeerModel {
  final String hostname;
  final String uuid;
  final String state;
  final bool connected;
  final bool isLocal;
  final int pingMs;
  final String checkedAt;

  GlusterPeerModel({
    required this.hostname,
    this.uuid = '',
    this.state = 'Peer in Cluster',
    this.connected = true,
    this.isLocal = false,
    this.pingMs = 0,
    this.checkedAt = '',
  });

  factory GlusterPeerModel.fromJson(Map<String, dynamic> json) {
    return GlusterPeerModel(
      hostname: json['hostname'] ?? '',
      uuid: json['uuid'] ?? '',
      state: json['state'] ?? 'Peer in Cluster',
      connected: json['connected'] != false,
      isLocal: json['is_local'] == true,
      pingMs: (json['ping_ms'] as num?)?.toInt() ?? 0,
      checkedAt: json['checked_at'] ?? '',
    );
  }
}

class GlusterBrickModel {
  final String path;
  final String host;
  final String fullSpec;
  final int port;
  final bool online;
  final int pid;
  final int sizeTotal;
  final int sizeFree;
  final bool isArbiter;

  GlusterBrickModel({
    required this.path,
    required this.host,
    required this.fullSpec,
    this.port = 49152,
    this.online = true,
    this.pid = 0,
    this.sizeTotal = 0,
    this.sizeFree = 0,
    this.isArbiter = false,
  });

  factory GlusterBrickModel.fromJson(Map<String, dynamic> json) {
    return GlusterBrickModel(
      path: json['path'] ?? '',
      host: json['host'] ?? '',
      fullSpec: json['full_spec'] ?? '',
      port: (json['port'] as num?)?.toInt() ?? 49152,
      online: json['online'] != false,
      pid: (json['pid'] as num?)?.toInt() ?? 0,
      sizeTotal: (json['size_total'] as num?)?.toInt() ?? 0,
      sizeFree: (json['size_free'] as num?)?.toInt() ?? 0,
      isArbiter: json['is_arbiter'] == true,
    );
  }
}

class GlusterVolumeModel {
  final String name;
  final String uuid;
  final String type;
  final String status;
  final int replicaCount;
  final int arbiterCount;
  final int numBricks;
  final String transport;
  final List<GlusterBrickModel> bricks;
  final Map<String, String> options;
  final bool isMounted;
  final String mountPoint;
  final int capacityTotal;
  final int capacityUsed;
  final int capacityFree;
  final double capacityPercent;
  final int pendingHeals;
  final String createdAt;

  GlusterVolumeModel({
    required this.name,
    this.uuid = '',
    this.type = 'Replicate',
    this.status = 'Started',
    this.replicaCount = 3,
    this.arbiterCount = 0,
    this.numBricks = 3,
    this.transport = 'tcp',
    this.bricks = const [],
    this.options = const {},
    this.isMounted = true,
    this.mountPoint = '/var/contenedores',
    this.capacityTotal = 0,
    this.capacityUsed = 0,
    this.capacityFree = 0,
    this.capacityPercent = 0.0,
    this.pendingHeals = 0,
    this.createdAt = '',
  });

  factory GlusterVolumeModel.fromJson(Map<String, dynamic> json) {
    List<GlusterBrickModel> brickList = [];
    if (json['bricks'] is List) {
      brickList = (json['bricks'] as List)
          .map((b) => GlusterBrickModel.fromJson(b as Map<String, dynamic>))
          .toList();
    }

    Map<String, String> opts = {};
    if (json['options'] is Map) {
      json['options'].forEach((k, v) => opts[k.toString()] = v.toString());
    }

    return GlusterVolumeModel(
      name: json['name'] ?? '',
      uuid: json['uuid'] ?? '',
      type: json['type'] ?? 'Replicate',
      status: json['status'] ?? 'Started',
      replicaCount: (json['replica_count'] as num?)?.toInt() ?? 3,
      arbiterCount: (json['arbiter_count'] as num?)?.toInt() ?? 0,
      numBricks: (json['num_bricks'] as num?)?.toInt() ?? brickList.length,
      transport: json['transport'] ?? 'tcp',
      bricks: brickList,
      options: opts,
      isMounted: json['is_mounted'] == true,
      mountPoint: json['mount_point'] ?? '/var/contenedores',
      capacityTotal: (json['capacity_total'] as num?)?.toInt() ?? 0,
      capacityUsed: (json['capacity_used'] as num?)?.toInt() ?? 0,
      capacityFree: (json['capacity_free'] as num?)?.toInt() ?? 0,
      capacityPercent: (json['capacity_percent'] as num?)?.toDouble() ?? 0.0,
      pendingHeals: (json['pending_heals'] as num?)?.toInt() ?? 0,
      createdAt: json['created_at'] ?? '',
    );
  }
}

class GlusterHealModel {
  final String volumeName;
  final int totalPending;
  final bool inSplitBrain;
  final int splitBrainCount;
  final List<GlusterBrickHealModel> bricksHealInfo;
  final String lastHealCheck;
  final String statusSummary;

  GlusterHealModel({
    required this.volumeName,
    this.totalPending = 0,
    this.inSplitBrain = false,
    this.splitBrainCount = 0,
    this.bricksHealInfo = const [],
    this.lastHealCheck = '',
    this.statusSummary = 'Healthy — 0 pending entries',
  });

  factory GlusterHealModel.fromJson(Map<String, dynamic> json) {
    List<GlusterBrickHealModel> bricks = [];
    if (json['bricks_heal_info'] is List) {
      bricks = (json['bricks_heal_info'] as List)
          .map((b) => GlusterBrickHealModel.fromJson(b as Map<String, dynamic>))
          .toList();
    }

    return GlusterHealModel(
      volumeName: json['volume_name'] ?? '',
      totalPending: (json['total_pending'] as num?)?.toInt() ?? 0,
      inSplitBrain: json['in_split_brain'] == true,
      splitBrainCount: (json['split_brain_count'] as num?)?.toInt() ?? 0,
      bricksHealInfo: bricks,
      lastHealCheck: json['last_heal_check'] ?? '',
      statusSummary: json['status_summary'] ?? '',
    );
  }
}

class GlusterBrickHealModel {
  final String brickSpec;
  final String status;
  final int numberOfEntries;
  final List<String> pendingFiles;

  GlusterBrickHealModel({
    required this.brickSpec,
    this.status = 'Connected',
    this.numberOfEntries = 0,
    this.pendingFiles = const [],
  });

  factory GlusterBrickHealModel.fromJson(Map<String, dynamic> json) {
    List<String> files = [];
    if (json['pending_files'] is List) {
      files = (json['pending_files'] as List).map((f) => f.toString()).toList();
    }
    return GlusterBrickHealModel(
      brickSpec: json['brick_spec'] ?? '',
      status: json['status'] ?? 'Connected',
      numberOfEntries: (json['number_of_entries'] as num?)?.toInt() ?? 0,
      pendingFiles: files,
    );
  }
}

class GlusterClusterDiagnosticsModel {
  final bool installed;
  final bool daemonRunning;
  final String version;
  final int peersCount;
  final int volumesCount;
  final int onlineVolumes;
  final bool quorumHealthy;
  final int healthScore;
  final List<String> issues;
  final List<GlusterPeerModel> peers;
  final String checkedAt;

  GlusterClusterDiagnosticsModel({
    this.installed = true,
    this.daemonRunning = true,
    this.version = '',
    this.peersCount = 3,
    this.volumesCount = 1,
    this.onlineVolumes = 1,
    this.quorumHealthy = true,
    this.healthScore = 100,
    this.issues = const [],
    this.peers = const [],
    this.checkedAt = '',
  });

  factory GlusterClusterDiagnosticsModel.fromJson(Map<String, dynamic> json) {
    List<String> issueList = [];
    if (json['issues'] is List) {
      issueList = (json['issues'] as List).map((i) => i.toString()).toList();
    }
    List<GlusterPeerModel> peerList = [];
    if (json['peers'] is List) {
      peerList = (json['peers'] as List)
          .map((p) => GlusterPeerModel.fromJson(p as Map<String, dynamic>))
          .toList();
    }
    return GlusterClusterDiagnosticsModel(
      installed: json['installed'] != false,
      daemonRunning: json['daemon_running'] != false,
      version: json['version'] ?? '',
      peersCount: (json['peers_count'] as num?)?.toInt() ?? 0,
      volumesCount: (json['volumes_count'] as num?)?.toInt() ?? 0,
      onlineVolumes: (json['online_volumes'] as num?)?.toInt() ?? 0,
      quorumHealthy: json['quorum_healthy'] != false,
      healthScore: (json['health_score'] as num?)?.toInt() ?? 100,
      issues: issueList,
      peers: peerList,
      checkedAt: json['checked_at'] ?? '',
    );
  }
}

/// Information and commands for joining a worker node into the cluster
class NodeJoinInfo {
  final String managerIp;
  final String managerHttp;
  final String joinToken;
  final String apiToken;
  final String managerPublicKey;
  final String oneLinerCmd;
  final String dockerCmd;
  final String cliCmd;
  final String cloudInitYaml;

  NodeJoinInfo({
    this.managerIp = '',
    this.managerHttp = '',
    this.joinToken = '',
    this.apiToken = '',
    this.managerPublicKey = '',
    this.oneLinerCmd = '',
    this.dockerCmd = '',
    this.cliCmd = '',
    this.cloudInitYaml = '',
  });

  factory NodeJoinInfo.fromJson(Map<String, dynamic> json) {
    return NodeJoinInfo(
      managerIp: json['manager_ip'] ?? '',
      managerHttp: json['manager_http'] ?? '',
      joinToken: json['join_token'] ?? '',
      apiToken: json['api_token'] ?? '',
      managerPublicKey: json['manager_public_key'] ?? '',
      oneLinerCmd: json['one_liner_cmd'] ?? '',
      dockerCmd: json['docker_cmd'] ?? '',
      cliCmd: json['cli_cmd'] ?? '',
      cloudInitYaml: json['cloud_init_yaml'] ?? '',
    );
  }
}

/// A step log entry generated during SSH node provisioning
class ProvisionStepLog {
  final String step;
  final String message;
  final String status; // "ok", "warn", "error", "running"

  ProvisionStepLog({required this.step, required this.message, required this.status});

  factory ProvisionStepLog.fromJson(Map<String, dynamic> json) {
    return ProvisionStepLog(
      step: json['step'] ?? '',
      message: json['message'] ?? '',
      status: json['status'] ?? 'ok',
    );
  }
}

/// Result returned from remote SSH node provisioning
class NodeProvisionResult {
  final bool success;
  final String message;
  final String? error;
  final List<ProvisionStepLog> logs;
  final Node? node;

  NodeProvisionResult({
    required this.success,
    required this.message,
    this.error,
    this.logs = const [],
    this.node,
  });
}

/// Image Security Auto-Remediation Candidate Version
class SuggestedVersionModel {
  final String version;
  final String type; // "patch", "alpine_stable", "latest"
  final String description;
  final String riskLevel; // "low", "medium", "high"
  final bool isRecommended;

  SuggestedVersionModel({
    required this.version,
    required this.type,
    required this.description,
    required this.riskLevel,
    required this.isRecommended,
  });

  factory SuggestedVersionModel.fromJson(Map<String, dynamic> json) {
    return SuggestedVersionModel(
      version: json['version'] ?? '',
      type: json['type'] ?? 'patch',
      description: json['description'] ?? '',
      riskLevel: json['risk_level'] ?? 'low',
      isRecommended: json['is_recommended'] == true,
    );
  }
}

/// Affected stack and service for a container image
class AffectedStackInfoModel {
  final String stackId;
  final String stackName;
  final String serviceName;
  final int replicas;

  AffectedStackInfoModel({
    required this.stackId,
    required this.stackName,
    required this.serviceName,
    required this.replicas,
  });

  factory AffectedStackInfoModel.fromJson(Map<String, dynamic> json) {
    return AffectedStackInfoModel(
      stackId: json['stack_id'] ?? '',
      stackName: json['stack_name'] ?? '',
      serviceName: json['service_name'] ?? '',
      replicas: (json['replicas'] as num?)?.toInt() ?? 1,
    );
  }
}

/// Preview and risk assessment for container image remediation
class RemediationPreviewModel {
  final String currentImage;
  final int criticalCount;
  final int highCount;
  final int mediumCount;
  final List<SuggestedVersionModel> suggestedVersions;
  final List<AffectedStackInfoModel> affectedStacks;
  final bool isInUse;
  final String riskAssessment;
  final String riskLevel;

  RemediationPreviewModel({
    required this.currentImage,
    required this.criticalCount,
    required this.highCount,
    required this.mediumCount,
    required this.suggestedVersions,
    required this.affectedStacks,
    this.isInUse = true,
    required this.riskAssessment,
    required this.riskLevel,
  });

  factory RemediationPreviewModel.fromJson(Map<String, dynamic> json) {
    return RemediationPreviewModel(
      currentImage: json['current_image'] ?? '',
      criticalCount: (json['critical_count'] as num?)?.toInt() ?? 0,
      highCount: (json['high_count'] as num?)?.toInt() ?? 0,
      mediumCount: (json['medium_count'] as num?)?.toInt() ?? 0,
      suggestedVersions: (json['suggested_versions'] as List<dynamic>? ?? [])
          .map((v) => SuggestedVersionModel.fromJson(v as Map<String, dynamic>))
          .toList(),
      affectedStacks: (json['affected_stacks'] as List<dynamic>? ?? [])
          .map((s) => AffectedStackInfoModel.fromJson(s as Map<String, dynamic>))
          .toList(),
      isInUse: json['is_in_use'] ?? ((json['affected_stacks'] as List<dynamic>? ?? []).isNotEmpty),
      riskAssessment: json['risk_assessment'] ?? '',
      riskLevel: json['risk_level'] ?? 'low',
    );
  }
}

/// Step log entry during automated image remediation & rollback
class RemediationStepLogModel {
  final String step;
  final String message;
  final String status; // "ok", "warn", "error"
  final String timestamp;

  RemediationStepLogModel({
    required this.step,
    required this.message,
    required this.status,
    required this.timestamp,
  });

  factory RemediationStepLogModel.fromJson(Map<String, dynamic> json) {
    return RemediationStepLogModel(
      step: json['step'] ?? '',
      message: json['message'] ?? '',
      status: json['status'] ?? 'ok',
      timestamp: json['timestamp'] ?? '',
    );
  }
}

/// Result of executing an automated image remediation
class RemediationResultModel {
  final bool success;
  final String message;
  final bool rolledBack;
  final String stackId;
  final String newImage;
  final String oldImage;
  final List<RemediationStepLogModel> logs;

  RemediationResultModel({
    required this.success,
    required this.message,
    required this.rolledBack,
    required this.stackId,
    required this.newImage,
    required this.oldImage,
    required this.logs,
  });

  factory RemediationResultModel.fromJson(Map<String, dynamic> json) {
    return RemediationResultModel(
      success: json['success'] == true,
      message: json['message'] ?? '',
      rolledBack: json['rolled_back'] == true,
      stackId: json['stack_id'] ?? '',
      newImage: json['new_image'] ?? '',
      oldImage: json['old_image'] ?? '',
      logs: (json['logs'] as List<dynamic>? ?? [])
          .map((l) => RemediationStepLogModel.fromJson(l as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Physical Docker image stored on a cluster node
class HostDockerImageModel {
  final String id;
  final String repository;
  final String tag;
  final String fullName;
  final String size;
  final int sizeBytes;
  final String createdAt;
  final String nodeId;
  final String nodeName;
  final String nodeIp;
  final bool inUse;
  final List<String> containersUsing;

  HostDockerImageModel({
    required this.id,
    required this.repository,
    required this.tag,
    required this.fullName,
    required this.size,
    required this.sizeBytes,
    required this.createdAt,
    required this.nodeId,
    required this.nodeName,
    required this.nodeIp,
    required this.inUse,
    this.containersUsing = const [],
  });

  factory HostDockerImageModel.fromJson(Map<String, dynamic> json) {
    return HostDockerImageModel(
      id: json['id'] ?? '',
      repository: json['repository'] ?? '',
      tag: json['tag'] ?? '',
      fullName: json['full_name'] ?? '',
      size: json['size'] ?? '',
      sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
      createdAt: json['created_at'] ?? '',
      nodeId: json['node_id'] ?? '',
      nodeName: json['node_name'] ?? '',
      nodeIp: json['node_ip'] ?? '',
      inUse: json['in_use'] == true,
      containersUsing: (json['containers_using'] as List<dynamic>? ?? [])
          .map((c) => c.toString())
          .toList(),
    );
  }
}

/// Single layer in an image construction history
class ImageLayerModel {
  final int order;
  final String id;
  final String createdBy;
  final String instruction;
  final String args;
  final String size;
  final int sizeBytes;
  final String createdAt;
  final String comment;

  ImageLayerModel({
    required this.order,
    required this.id,
    required this.createdBy,
    required this.instruction,
    required this.args,
    required this.size,
    required this.sizeBytes,
    required this.createdAt,
    required this.comment,
  });

  factory ImageLayerModel.fromJson(Map<String, dynamic> json) {
    return ImageLayerModel(
      order: (json['order'] as num?)?.toInt() ?? 0,
      id: json['id'] ?? '',
      createdBy: json['created_by'] ?? '',
      instruction: json['instruction'] ?? '',
      args: json['args'] ?? '',
      size: json['size'] ?? '',
      sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
      createdAt: json['created_at'] ?? '',
      comment: json['comment'] ?? '',
    );
  }
}

/// Complete layer breakdown and reconstructed Dockerfile
class ImageHistoryModel {
  final String image;
  final String imageId;
  final String nodeId;
  final String nodeName;
  final List<ImageLayerModel> layers;
  final String reconstructedDockerfile;
  final int totalSizeBytes;
  final String totalSize;

  ImageHistoryModel({
    required this.image,
    required this.imageId,
    required this.nodeId,
    required this.nodeName,
    required this.layers,
    required this.reconstructedDockerfile,
    required this.totalSizeBytes,
    required this.totalSize,
  });

  factory ImageHistoryModel.fromJson(Map<String, dynamic> json) {
    return ImageHistoryModel(
      image: json['image'] ?? '',
      imageId: json['image_id'] ?? '',
      nodeId: json['node_id'] ?? '',
      nodeName: json['node_name'] ?? '',
      layers: (json['layers'] as List<dynamic>? ?? [])
          .map((l) => ImageLayerModel.fromJson(l as Map<String, dynamic>))
          .toList(),
      reconstructedDockerfile: json['reconstructed_dockerfile'] ?? '',
      totalSizeBytes: (json['total_size_bytes'] as num?)?.toInt() ?? 0,
      totalSize: json['total_size'] ?? '',
    );
  }
}

/// Outcome of docker image prune operation across cluster nodes
class ImagePruneResultModel {
  final int totalImagesDeleted;
  final String totalSpaceReclaimed;
  final int totalSpaceReclaimedBytes;
  final Map<String, String> nodeResults;
  final List<String> logs;

  ImagePruneResultModel({
    required this.totalImagesDeleted,
    required this.totalSpaceReclaimed,
    required this.totalSpaceReclaimedBytes,
    required this.nodeResults,
    required this.logs,
  });

  factory ImagePruneResultModel.fromJson(Map<String, dynamic> json) {
    Map<String, String> nodeRes = {};
    if (json['node_results'] is Map) {
      (json['node_results'] as Map).forEach((k, v) {
        nodeRes[k.toString()] = v.toString();
      });
    }

    return ImagePruneResultModel(
      totalImagesDeleted: (json['total_images_deleted'] as num?)?.toInt() ?? 0,
      totalSpaceReclaimed: json['total_space_reclaimed'] ?? '0 B',
      totalSpaceReclaimedBytes: (json['total_space_reclaimed_bytes'] as num?)?.toInt() ?? 0,
      nodeResults: nodeRes,
      logs: (json['logs'] as List<dynamic>? ?? []).map((l) => l.toString()).toList(),
    );
  }
}

/// Outcome of Dockerfile build execution in The Forge
class ImageBuildResultModel {
  final bool success;
  final String imageTag;
  final String imageId;
  final String nodeId;
  final String nodeName;
  final String duration;
  final List<String> logs;
  final String? error;

  ImageBuildResultModel({
    required this.success,
    required this.imageTag,
    required this.imageId,
    required this.nodeId,
    required this.nodeName,
    required this.duration,
    required this.logs,
    this.error,
  });

  factory ImageBuildResultModel.fromJson(Map<String, dynamic> json) {
    return ImageBuildResultModel(
      success: json['success'] == true,
      imageTag: json['image_tag'] ?? '',
      imageId: json['image_id'] ?? '',
      nodeId: json['node_id'] ?? '',
      nodeName: json['node_name'] ?? '',
      duration: json['duration'] ?? '',
      logs: (json['logs'] as List<dynamic>? ?? []).map((l) => l.toString()).toList(),
      error: json['error'],
    );
  }
}

/// Outcome of distributing an image across Centurion cluster nodes
class ImageDistributeResultModel {
  final bool success;
  final String image;
  final String sourceNode;
  final List<String> targetNodes;
  final Map<String, String> nodeResults;
  final String duration;
  final String? error;

  ImageDistributeResultModel({
    required this.success,
    required this.image,
    required this.sourceNode,
    required this.targetNodes,
    required this.nodeResults,
    required this.duration,
    this.error,
  });

  factory ImageDistributeResultModel.fromJson(Map<String, dynamic> json) {
    final rawResults = json['node_results'] as Map<String, dynamic>? ?? {};
    final nodeResults = rawResults.map((k, v) => MapEntry(k, v.toString()));
    return ImageDistributeResultModel(
      success: json['success'] == true,
      image: json['image'] ?? '',
      sourceNode: json['source_node'] ?? '',
      targetNodes: (json['target_nodes'] as List<dynamic>? ?? []).map((t) => t.toString()).toList(),
      nodeResults: nodeResults,
      duration: json['duration'] ?? '',
      error: json['error'],
    );
  }
}

class ServerStackFileModel {
  final String path;
  final String filename;
  final String directory;
  final int size;
  final String modifiedAt;
  final String inferredName;
  final bool isExample;
  final int services;

  ServerStackFileModel({
    required this.path,
    required this.filename,
    required this.directory,
    required this.size,
    required this.modifiedAt,
    required this.inferredName,
    required this.isExample,
    required this.services,
  });

  factory ServerStackFileModel.fromJson(Map<String, dynamic> json) {
    return ServerStackFileModel(
      path: json['path'] ?? '',
      filename: json['filename'] ?? '',
      directory: json['directory'] ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      modifiedAt: json['modified_at'] ?? '',
      inferredName: json['inferred_name'] ?? '',
      isExample: json['is_example'] == true,
      services: (json['services'] as num?)?.toInt() ?? 0,
    );
  }
}

class POCExampleModel {
  final String id;
  final String name;
  final String category;
  final String description;
  final String filename;
  final String defaultStack;
  final List<String> services;
  final String composeRaw;
  final String icon;
  final List<String> tags;

  POCExampleModel({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.filename,
    required this.defaultStack,
    required this.services,
    required this.composeRaw,
    required this.icon,
    required this.tags,
  });

  factory POCExampleModel.fromJson(Map<String, dynamic> json) {
    return POCExampleModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      category: json['category'] ?? '',
      description: json['description'] ?? '',
      filename: json['filename'] ?? '',
      defaultStack: json['default_stack'] ?? '',
      services: (json['services'] as List<dynamic>? ?? []).map((s) => s.toString()).toList(),
      composeRaw: json['compose_raw'] ?? '',
      icon: json['icon'] ?? '',
      tags: (json['tags'] as List<dynamic>? ?? []).map((t) => t.toString()).toList(),
    );
  }
}

/// Host port collision metadata returned during stack scheduling conflict
class PortConflictModel {
  final int hostPort;
  final String protocol;
  final String service;
  final String conflictingStack;
  final String conflictingService;
  final String nodeId;
  final String nodeIp;
  final int suggestedPort;

  PortConflictModel({
    required this.hostPort,
    required this.protocol,
    required this.service,
    required this.conflictingStack,
    required this.conflictingService,
    required this.nodeId,
    required this.nodeIp,
    required this.suggestedPort,
  });

  factory PortConflictModel.fromJson(Map<String, dynamic> json) {
    return PortConflictModel(
      hostPort: (json['host_port'] as num?)?.toInt() ?? 0,
      protocol: json['protocol'] ?? 'tcp',
      service: json['service'] ?? '',
      conflictingStack: json['conflicting_stack'] ?? '',
      conflictingService: json['conflicting_service'] ?? '',
      nodeId: json['node_id'] ?? '',
      nodeIp: json['node_ip'] ?? '',
      suggestedPort: (json['suggested_port'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Result of deploying a stack, capturing success, error, or port conflict metadata
class DeployStackResult {
  final bool success;
  final String? error;
  final bool isConflict;
  final List<PortConflictModel> conflicts;
  final String? remappedCompose;
  final String? stackId;

  DeployStackResult({
    required this.success,
    this.error,
    this.isConflict = false,
    this.conflicts = const [],
    this.remappedCompose,
    this.stackId,
  });
}

// ── eBPF Live Hub Models ──────────────────────────────────────────────────

class EbpfInterfaceStats {
  final String name;
  final int rxBytes;
  final int txBytes;
  final int rxPackets;
  final int txPackets;
  final int rxErrors;
  final int txErrors;
  final int rxDrops;
  final int txDrops;

  EbpfInterfaceStats({
    required this.name,
    this.rxBytes = 0,
    this.txBytes = 0,
    this.rxPackets = 0,
    this.txPackets = 0,
    this.rxErrors = 0,
    this.txErrors = 0,
    this.rxDrops = 0,
    this.txDrops = 0,
  });

  factory EbpfInterfaceStats.fromJson(Map<String, dynamic> json) {
    return EbpfInterfaceStats(
      name: json['name'] ?? '',
      rxBytes: (json['rx_bytes'] as num?)?.toInt() ?? 0,
      txBytes: (json['tx_bytes'] as num?)?.toInt() ?? 0,
      rxPackets: (json['rx_packets'] as num?)?.toInt() ?? 0,
      txPackets: (json['tx_packets'] as num?)?.toInt() ?? 0,
      rxErrors: (json['rx_errors'] as num?)?.toInt() ?? 0,
      txErrors: (json['tx_errors'] as num?)?.toInt() ?? 0,
      rxDrops: (json['rx_drops'] as num?)?.toInt() ?? 0,
      txDrops: (json['tx_drops'] as num?)?.toInt() ?? 0,
    );
  }
}

class EbpfStats {
  final String kernelVersion;
  final bool ebpfSupported;
  final String mode;
  final int activeProbes;
  final List<String> probesList;
  final int totalFlows;
  final int activeFlows;
  final double packetsPerSec;
  final double bytesPerSec;
  final int droppedPackets;
  final List<EbpfInterfaceStats> interfaces;
  final Map<String, int> protocolCounts;
  final Map<String, int> statusCounts;

  EbpfStats({
    required this.kernelVersion,
    required this.ebpfSupported,
    this.mode = 'kernel',
    this.activeProbes = 0,
    this.probesList = const [],
    this.totalFlows = 0,
    this.activeFlows = 0,
    this.packetsPerSec = 0.0,
    this.bytesPerSec = 0.0,
    this.droppedPackets = 0,
    this.interfaces = const [],
    this.protocolCounts = const {},
    this.statusCounts = const {},
  });

  factory EbpfStats.fromJson(Map<String, dynamic> json) {
    final ifacesList = <EbpfInterfaceStats>[];
    if (json['interfaces'] != null && json['interfaces'] is List) {
      for (final item in json['interfaces']) {
        if (item is Map<String, dynamic>) {
          ifacesList.add(EbpfInterfaceStats.fromJson(item));
        }
      }
    }

    final probes = <String>[];
    if (json['probes_list'] != null && json['probes_list'] is List) {
      for (final p in json['probes_list']) {
        probes.add(p.toString());
      }
    }

    final protoCounts = <String, int>{};
    if (json['protocol_counts'] != null && json['protocol_counts'] is Map) {
      json['protocol_counts'].forEach((k, v) {
        protoCounts[k.toString()] = (v as num?)?.toInt() ?? 0;
      });
    }

    final statCounts = <String, int>{};
    if (json['status_counts'] != null && json['status_counts'] is Map) {
      json['status_counts'].forEach((k, v) {
        statCounts[k.toString()] = (v as num?)?.toInt() ?? 0;
      });
    }

    return EbpfStats(
      kernelVersion: json['kernel_version'] ?? '',
      ebpfSupported: json['ebpf_supported'] == true,
      mode: json['mode'] ?? 'kernel',
      activeProbes: (json['active_probes'] as num?)?.toInt() ?? 0,
      probesList: probes,
      totalFlows: (json['total_flows'] as num?)?.toInt() ?? 0,
      activeFlows: (json['active_flows'] as num?)?.toInt() ?? 0,
      packetsPerSec: (json['packets_per_sec'] as num?)?.toDouble() ?? 0.0,
      bytesPerSec: (json['bytes_per_sec'] as num?)?.toDouble() ?? 0.0,
      droppedPackets: (json['dropped_packets'] as num?)?.toInt() ?? 0,
      interfaces: ifacesList,
      protocolCounts: protoCounts,
      statusCounts: statCounts,
    );
  }
}

class EbpfFlow {
  final String id;
  final String sourceId;
  final String sourceName;
  final String sourceIp;
  final int sourcePort;
  final String destId;
  final String destName;
  final String destIp;
  final int destPort;
  final String protocol;
  final String method;
  final String path;
  final int statusCode;
  final double latencyMs;
  final int bytesSent;
  final int bytesReceived;
  final double throughputBps;
  final int retransmits;
  final int drops;
  final String traceId;
  final String status;
  final DateTime timestamp;

  EbpfFlow({
    required this.id,
    required this.sourceId,
    required this.sourceName,
    required this.sourceIp,
    this.sourcePort = 0,
    required this.destId,
    required this.destName,
    required this.destIp,
    this.destPort = 0,
    required this.protocol,
    this.method = '',
    this.path = '',
    this.statusCode = 0,
    this.latencyMs = 0.0,
    this.bytesSent = 0,
    this.bytesReceived = 0,
    this.throughputBps = 0.0,
    this.retransmits = 0,
    this.drops = 0,
    this.traceId = '',
    required this.status,
    required this.timestamp,
  });

  factory EbpfFlow.fromJson(Map<String, dynamic> json) {
    DateTime ts = DateTime.now();
    if (json['timestamp'] != null) {
      ts = DateTime.tryParse(json['timestamp'].toString()) ?? DateTime.now();
    }

    return EbpfFlow(
      id: json['id'] ?? '',
      sourceId: json['source_id'] ?? '',
      sourceName: json['source_name'] ?? '',
      sourceIp: json['source_ip'] ?? '',
      sourcePort: (json['source_port'] as num?)?.toInt() ?? 0,
      destId: json['dest_id'] ?? '',
      destName: json['dest_name'] ?? '',
      destIp: json['dest_ip'] ?? '',
      destPort: (json['dest_port'] as num?)?.toInt() ?? 0,
      protocol: json['protocol'] ?? 'TCP',
      method: json['method'] ?? '',
      path: json['path'] ?? '',
      statusCode: (json['status_code'] as num?)?.toInt() ?? 0,
      latencyMs: (json['latency_ms'] as num?)?.toDouble() ?? 0.0,
      bytesSent: (json['bytes_sent'] as num?)?.toInt() ?? 0,
      bytesReceived: (json['bytes_received'] as num?)?.toInt() ?? 0,
      throughputBps: (json['throughput_bps'] as num?)?.toDouble() ?? 0.0,
      retransmits: (json['retransmits'] as num?)?.toInt() ?? 0,
      drops: (json['drops'] as num?)?.toInt() ?? 0,
      traceId: json['trace_id'] ?? '',
      status: json['status'] ?? 'healthy',
      timestamp: ts,
    );
  }
}

class EbpfTopologyNode {
  final String id;
  final String name;
  final String type;
  final String stack;
  final String nodeHost;
  final String ip;
  final String status;
  final double inboundBps;
  final double outboundBps;
  final int activeFlows;
  final double errorRate;
  final double cpuPercent;
  final double memPercent;

  EbpfTopologyNode({
    required this.id,
    required this.name,
    required this.type,
    this.stack = '',
    this.nodeHost = '',
    this.ip = '',
    this.status = 'running',
    this.inboundBps = 0.0,
    this.outboundBps = 0.0,
    this.activeFlows = 0,
    this.errorRate = 0.0,
    this.cpuPercent = 0.0,
    this.memPercent = 0.0,
  });

  factory EbpfTopologyNode.fromJson(Map<String, dynamic> json) {
    return EbpfTopologyNode(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      type: json['type'] ?? 'container',
      stack: json['stack'] ?? '',
      nodeHost: json['node_host'] ?? '',
      ip: json['ip'] ?? '',
      status: json['status'] ?? 'running',
      inboundBps: (json['inbound_bps'] as num?)?.toDouble() ?? 0.0,
      outboundBps: (json['outbound_bps'] as num?)?.toDouble() ?? 0.0,
      activeFlows: (json['active_flows'] as num?)?.toInt() ?? 0,
      errorRate: (json['error_rate'] as num?)?.toDouble() ?? 0.0,
      cpuPercent: (json['cpu_percent'] as num?)?.toDouble() ?? 0.0,
      memPercent: (json['mem_percent'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class EbpfTopologyEdge {
  final String id;
  final String sourceId;
  final String targetId;
  final String protocol;
  final double throughputBps;
  final double rttMs;
  final int activeFlows;
  final double errorRate;
  final String traceId;
  final String status;
  final DateTime lastSeen;

  EbpfTopologyEdge({
    required this.id,
    required this.sourceId,
    required this.targetId,
    required this.protocol,
    this.throughputBps = 0.0,
    this.rttMs = 0.0,
    this.activeFlows = 0,
    this.errorRate = 0.0,
    this.traceId = '',
    this.status = 'healthy',
    required this.lastSeen,
  });

  factory EbpfTopologyEdge.fromJson(Map<String, dynamic> json) {
    DateTime ls = DateTime.now();
    if (json['last_seen'] != null) {
      ls = DateTime.tryParse(json['last_seen'].toString()) ?? DateTime.now();
    }
    return EbpfTopologyEdge(
      id: json['id'] ?? '',
      sourceId: json['source_id'] ?? '',
      targetId: json['target_id'] ?? '',
      protocol: json['protocol'] ?? 'TCP',
      throughputBps: (json['throughput_bps'] as num?)?.toDouble() ?? 0.0,
      rttMs: (json['rtt_ms'] as num?)?.toDouble() ?? 0.0,
      activeFlows: (json['active_flows'] as num?)?.toInt() ?? 0,
      errorRate: (json['error_rate'] as num?)?.toDouble() ?? 0.0,
      traceId: json['trace_id'] ?? '',
      status: json['status'] ?? 'healthy',
      lastSeen: ls,
    );
  }
}

class EbpfTopology {
  final List<EbpfTopologyNode> nodes;
  final List<EbpfTopologyEdge> edges;
  final DateTime updatedAt;

  EbpfTopology({
    required this.nodes,
    required this.edges,
    required this.updatedAt,
  });

  factory EbpfTopology.fromJson(Map<String, dynamic> json) {
    final nList = <EbpfTopologyNode>[];
    if (json['nodes'] != null && json['nodes'] is List) {
      for (final n in json['nodes']) {
        if (n is Map<String, dynamic>) {
          nList.add(EbpfTopologyNode.fromJson(n));
        }
      }
    }

    final eList = <EbpfTopologyEdge>[];
    if (json['edges'] != null && json['edges'] is List) {
      for (final e in json['edges']) {
        if (e is Map<String, dynamic>) {
          eList.add(EbpfTopologyEdge.fromJson(e));
        }
      }
    }

    DateTime u = DateTime.now();
    if (json['updated_at'] != null) {
      u = DateTime.tryParse(json['updated_at'].toString()) ?? DateTime.now();
    }

    return EbpfTopology(
      nodes: nList,
      edges: eList,
      updatedAt: u,
    );
  }
}


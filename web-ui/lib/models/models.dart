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
      netBps: (json['net_bps'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class StackModel {
  final String id;
  final String name;
  final String rawComposeFile;
  final String createdAt;

  StackModel({
    required this.id,
    required this.name,
    this.rawComposeFile = '',
    this.createdAt = '',
  });

  factory StackModel.fromJson(Map<String, dynamic> json) {
    return StackModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      rawComposeFile: json['raw_compose_file'] ?? '',
      createdAt: json['created_at'] ?? '',
    );
  }
}

class Service {
  final String id;
  final String stackId;
  final String name;
  final String image;
  final int desiredReplicas;
  final List<String> ports;

  Service({
    required this.id,
    required this.stackId,
    required this.name,
    required this.image,
    this.desiredReplicas = 1,
    this.ports = const [],
  });

  factory Service.fromJson(Map<String, dynamic> json) {
    return Service(
      id: json['id'] ?? '',
      stackId: json['stack_id'] ?? '',
      name: json['name'] ?? '',
      image: json['image'] ?? '',
      desiredReplicas: json['desired_replicas'] ?? 1,
      ports: (json['ports'] as List?)?.map((e) => e.toString()).toList() ?? [],
    );
  }
}

class Task {
  final String id;
  final String serviceId;
  final String nodeId;
  final String status;
  final String containerName;
  final String containerIp;
  final String createdAt;

  Task({
    required this.id,
    required this.serviceId,
    required this.nodeId,
    required this.status,
    this.containerName = '',
    this.containerIp = '',
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
  final String clusterJoinToken;
  final String activeApiToken;
  final String managerIp;
  final bool updateAvailable;
  final String latestVersion;
  final String releaseNotes;
  final String releaseUrl;
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
    this.version = 'dev',
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
      version: json['version'] ?? 'dev',
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
    );
  }
}

class UserSession {
  final String username;
  final String displayName;
  final String email;
  final String role; // "admin", "operator", "readonly"
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
  final String type; // "local", "ldap"

  const AuthProvider({
    required this.id,
    required this.name,
    required this.type,
  });

  factory AuthProvider.fromJson(Map<String, dynamic> json) {
    return AuthProvider(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      type: json['type'] ?? 'local',
    );
  }
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

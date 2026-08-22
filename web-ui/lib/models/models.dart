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


class LocalUser {
  final String id;
  final String username;
  final String displayName;
  final String email;
  final String role;
  final bool enabled;
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

  AuditLog({
    required this.id,
    required this.timestamp,
    required this.username,
    required this.provider,
    required this.ipAddress,
    required this.action,
    required this.status,
    required this.details,
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
  final String sourcePath;
  final String targetPath;
  final String stackId;
  final String stackName;
  final String serviceName;
  final String nodeId;
  final int sizeBytes;
  final String sizeFormatted;
  final bool isShared;
  final String lastScannedAt;

  StorageVolumeModel({
    required this.id,
    required this.name,
    required this.type,
    required this.sourcePath,
    required this.targetPath,
    this.stackId = '',
    this.stackName = '',
    this.serviceName = '',
    this.nodeId = 'cluster',
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
      sourcePath: json['source_path'] ?? '',
      targetPath: json['target_path'] ?? '',
      stackId: json['stack_id'] ?? '',
      stackName: json['stack_name'] ?? '',
      serviceName: json['service_name'] ?? '',
      nodeId: json['node_id'] ?? 'cluster',
      sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
      sizeFormatted: json['size_formatted'] ?? '0 B',
      isShared: json['is_shared'] == true,
      lastScannedAt: json['last_scanned_at'] ?? '',
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
  final String createdAt;

  TrustedKeyModel({
    required this.id,
    required this.name,
    required this.publicKeyPem,
    this.keyType = 'cosign-ecdsa',
    this.isDefault = false,
    required this.createdAt,
  });

  factory TrustedKeyModel.fromJson(Map<String, dynamic> json) {
    return TrustedKeyModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      publicKeyPem: json['public_key_pem'] ?? '',
      keyType: json['key_type'] ?? 'cosign-ecdsa',
      isDefault: json['is_default'] ?? false,
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




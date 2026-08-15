import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/models.dart';

/// Service class to communicate with the Gubernator backend API.
class ApiService {
  /// Fetches the full dashboard state from the backend.
  static Future<DashboardState> fetchState() async {
    final response = await http.get(Uri.parse('/api/state'));
    if (response.statusCode == 200) {
      return DashboardState.fromJson(jsonDecode(response.body));
    }
    throw Exception('Failed to fetch state: ${response.statusCode}');
  }

  /// Deletes a stack and stops all its containers.
  static Future<bool> deleteStack(String id) async {
    final response = await http.delete(Uri.parse('/api/stack/$id'));
    return response.statusCode == 200;
  }

  /// Redeploys a stack.
  static Future<bool> redeployStack(String id) async {
    final response = await http.post(Uri.parse('/api/stack/$id/redeploy'));
    return response.statusCode == 200;
  }

  static Future<String?> deployStack(String name, String compose, {String? targetNode}) async {
    final response = await http.post(
      Uri.parse('/api/stack'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'compose': compose,
        'target_node': targetNode,
      }),
    );
    if (response.statusCode == 200) {
      return null;
    } else {
      try {
        final body = jsonDecode(response.body);
        return body['error'] ?? 'Unknown error';
      } catch (_) {
        return 'Server error: ${response.statusCode}';
      }
    }
  }

  /// Stops/removes a single task.
  static Future<bool> deleteTask(String id) async {
    final response = await http.delete(Uri.parse('/api/task/$id'));
    return response.statusCode == 200;
  }

  /// Migrates a stack to a target node.
  static Future<bool> migrateStack(String stackId, String targetNode) async {
    final response = await http.post(
      Uri.parse('/api/stack/$stackId/migrate'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'target_node': targetNode}),
    );
    return response.statusCode == 200;
  }

  /// Provision and add a remote worker host via SSH.
  static Future<String?> addHost(String host, String user, String password) async {
    try {
      final response = await http.post(
        Uri.parse('/api/node/add'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'host': host,
          'user': user,
          'password': password,
        }),
      );
      if (response.statusCode == 200) {
        return null; // Success
      } else {
        final body = jsonDecode(response.body);
        return body['error'] ?? 'Failed to add host';
      }
    } catch (e) {
      return e.toString();
    }
  }

  /// Sends an action (pause, unpause, restart, start, stop) to a task
  static Future<bool> taskAction(String id, String action) async {
    final response = await http.post(
      Uri.parse('/api/task/$id/action'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'action': action}),
    );
    return response.statusCode == 200;
  }

  /// Gets tail logs for a task
  static Future<String> taskLogs(String id) async {
    final response = await http.get(Uri.parse('/api/task/$id/logs'));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['logs'] ?? '';
    }
    throw Exception('Failed to fetch logs: ${response.statusCode}');
  }

  /// Gets inspect JSON for a task
  static Future<String> taskInspect(String id) async {
    final response = await http.get(Uri.parse('/api/task/$id/inspect'));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return const JsonEncoder.withIndent('  ').convert(data);
    }
    throw Exception('Failed to fetch inspect data: ${response.statusCode}');
  }

  /// Gets the compose YAML for a specific stack.
  static Future<String> getStackCompose(String id) async {
    final response = await http.get(Uri.parse('/api/stack/$id/compose'));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['compose'] ?? '';
    }
    throw Exception('Failed to fetch compose');
  }

  /// Saves updated compose YAML for a stack.
  static Future<bool> updateStackCompose(String id, String compose) async {
    final response = await http.put(
      Uri.parse('/api/stack/$id/compose'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'compose': compose}),
    );
    return response.statusCode == 200;
  }

  /// Fetches user settings from the backend.
  static Future<Map<String, dynamic>> getSettings() async {
    final response = await http.get(Uri.parse('/api/settings'));
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return {};
  }

  /// Updates user settings on the backend.
  static Future<bool> updateSettings(Map<String, dynamic> settings) async {
    final response = await http.put(
      Uri.parse('/api/settings'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(settings),
    );
    return response.statusCode == 200;
  }

  /// Changes the web dashboard password.
  static Future<bool> changePassword(
      String currentPassword, String newPassword) async {
    final response = await http.put(
      Uri.parse('/api/settings/password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'current_password': currentPassword,
        'new_password': newPassword,
      }),
    );
    return response.statusCode == 200;
  }

  /// Updates a node's role (promote/demote).
  static Future<bool> updateNodeRole(String id, String role) async {
    final response = await http.post(
      Uri.parse('/api/node/$id/role'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'role': role}),
    );
    return response.statusCode == 200;
  }

  /// Updates a node's availability status. Returns parsed response Map.
  static Future<Map<String, dynamic>> updateNodeAvailability(String id, String availability) async {
    try {
      final response = await http.post(
        Uri.parse('/api/node/$id/availability'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'availability': availability}),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return {'error': 'Failed with status ${response.statusCode}'};
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// Synchronizes the active authentication token to the remote worker node via SSH.
  static Future<Map<String, dynamic>> syncNodeToken(String id) async {
    try {
      final response = await http.post(Uri.parse('/api/node/$id/sync-token'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      final body = jsonDecode(response.body);
      return {'error': body['error'] ?? 'Failed to sync token'};
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// Commands the node to leave the cluster.
  static Future<bool> leaveNode(String id) async {
    final response = await http.post(Uri.parse('/api/node/$id/leave'));
    return response.statusCode == 200;
  }

  /// Triggers a reboot for the node.
  static Future<bool> rebootNode(String id) async {
    final response = await http.post(Uri.parse('/api/node/$id/reboot'));
    return response.statusCode == 200;
  }

  /// Updates a node's labels.
  static Future<bool> updateNodeLabels(String id, Map<String, String> labels) async {
    final response = await http.post(
      Uri.parse('/api/node/$id/labels'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'labels': labels}),
    );
    return response.statusCode == 200;
  }

  /// Gets the CoreDNS configuration (Corefile).
  static Future<String> getCoreDNSConfig() async {
    final response = await http.get(Uri.parse('/api/coredns/config'));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['config'] ?? '';
    }
    throw Exception('Failed to fetch CoreDNS config');
  }

  /// Updates the CoreDNS configuration (Corefile).
  static Future<bool> updateCoreDNSConfig(String config) async {
    final response = await http.put(
      Uri.parse('/api/coredns/config'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'config': config}),
    );
    return response.statusCode == 200;
  }

  /// Fetches CoreDNS status and memory usage.
  static Future<CoreDNSStatusInfo> fetchCoreDNSStatusInfo() async {
    final response = await http.get(Uri.parse('/api/coredns/status'));
    if (response.statusCode == 200) {
      return CoreDNSStatusInfo.fromJson(jsonDecode(response.body));
    }
    return CoreDNSStatusInfo(status: 'stopped', uptimeSeconds: 0, memBytes: 0, listeningPort: 5354, forwarders: [], totalRecords: 0);
  }

  /// Fetches custom static DNS records.
  static Future<List<CustomDNSRecord>> fetchCustomDNSRecords() async {
    final response = await http.get(Uri.parse('/api/coredns/custom-records'));
    if (response.statusCode == 200) {
      final List list = jsonDecode(response.body);
      return list.map((e) => CustomDNSRecord.fromJson(e)).toList();
    }
    return [];
  }

  /// Creates a custom static DNS record.
  static Future<bool> createCustomDNSRecord({
    required String domain,
    required String ip,
    String recordType = 'A',
    int ttl = 60,
  }) async {
    final response = await http.post(
      Uri.parse('/api/coredns/custom-records'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'domain': domain,
        'ip': ip,
        'record_type': recordType,
        'ttl': ttl,
      }),
    );
    return response.statusCode == 201;
  }

  /// Deletes a custom static DNS record.
  static Future<bool> deleteCustomDNSRecord(String id) async {
    final response = await http.delete(Uri.parse('/api/coredns/custom-records/$id'));
    return response.statusCode == 200;
  }

  /// Performs an interactive DNS query test (Dig / Nslookup).
  static Future<DNSDigResult> performDNSDig({
    required String domain,
    String recordType = 'A',
  }) async {
    final response = await http.post(
      Uri.parse('/api/coredns/dig'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'domain': domain,
        'record_type': recordType,
      }),
    );
    if (response.statusCode == 200) {
      return DNSDigResult.fromJson(jsonDecode(response.body));
    }
    return DNSDigResult(domain: domain, recordType: recordType, status: 'ERROR', queryTimeMs: 0.0, server: '127.0.0.1:5354', answers: [], rawOutput: 'Error connecting to server');
  }

  /// Fetches status of Weave Scope Network Topology superpower.
  static Future<Map<String, dynamic>> fetchScopeStatus() async {
    final response = await http.get(Uri.parse('/api/scope/status'));
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return {'enabled': false, 'status': 'stopped'};
  }

  /// Enables Weave Scope container.
  static Future<bool> enableScope() async {
    final response = await http.post(Uri.parse('/api/scope/enable'));
    return response.statusCode == 200;
  }

  /// Disables Weave Scope container.
  static Future<bool> disableScope() async {
    final response = await http.post(Uri.parse('/api/scope/disable'));
    return response.statusCode == 200;
  }

  /// Triggers cluster auto-update.
  static Future<bool> applyUpdate(String targetVersion) async {
    final response = await http.post(
      Uri.parse('/api/update/apply'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'target_version': targetVersion}),
    );
    return response.statusCode == 200;
  }

  /// Fetches active SLO definitions and error budgets.
  static Future<List<SLOItem>> fetchSLOs() async {
    final response = await http.get(Uri.parse('/api/slo'));
    if (response.statusCode == 200) {
      final List list = jsonDecode(response.body);
      return list.map((e) => SLOItem.fromJson(e)).toList();
    }
    return [];
  }

  /// Force syncs SLO rules with Prometheus.
  static Future<bool> syncSLOs() async {
    final response = await http.post(Uri.parse('/api/slo/sync'));
    return response.statusCode == 200;
  }

  /// Fetches aggregated User Journeys.
  static Future<List<UserJourney>> fetchUserJourneys() async {
    final response = await http.get(Uri.parse('/api/slo/journeys'));
    if (response.statusCode == 200) {
      final List list = jsonDecode(response.body);
      return list.map((e) => UserJourney.fromJson(e)).toList();
    }
    return [];
  }

  /// Fetches deployment events correlation.
  static Future<List<SLOCorrelationEvent>> fetchSLOCorrelations() async {
    final response = await http.get(Uri.parse('/api/slo/correlation'));
    if (response.statusCode == 200) {
      final List list = jsonDecode(response.body);
      return list.map((e) => SLOCorrelationEvent.fromJson(e)).toList();
    }
    return [];
  }

  /// Validates Compose YAML and runs PromQL backtest.
  static Future<List<SLOValidationItem>> validateSLO(String composeRaw) async {
    final response = await http.post(
      Uri.parse('/api/slo/validate'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'compose_raw': composeRaw}),
    );
    if (response.statusCode == 200) {
      final List list = jsonDecode(response.body);
      return list.map((e) => SLOValidationItem.fromJson(e)).toList();
    }
    return [];
  }

  /// Fetches historical trend points for an SLO.
  static Future<List<SLOHistoryPoint>> fetchSLOHistory(String serviceId, String timeRange) async {
    final response = await http.get(Uri.parse('/api/slo/history?service_id=$serviceId&range=$timeRange'));
    if (response.statusCode == 200) {
      final List list = jsonDecode(response.body);
      return list.map((e) => SLOHistoryPoint.fromJson(e)).toList();
    }
    return [];
  }

  /// Fetches RED metrics for a service.
  static Future<SLOREDMetrics> fetchSLOREDMetrics(String serviceId) async {
    final response = await http.get(Uri.parse('/api/slo/red?service_id=$serviceId'));
    if (response.statusCode == 200) {
      return SLOREDMetrics.fromJson(jsonDecode(response.body));
    }
    return SLOREDMetrics(rps: 0, errorRps: 0, p99LatencyMs: 0);
  }

  /// Creates or updates an SLO configuration for a service.
  static Future<bool> editSLO({
    required String serviceId,
    required bool enable,
    required double target,
    required String window,
    String indicator = 'ratio',
    String latencyThreshold = '',
    String template = '',
    String journey = '',
    String errorQuery = '',
    String totalQuery = '',
  }) async {
    final response = await http.post(
      Uri.parse('/api/slo/edit'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'service_id': serviceId,
        'enable': enable,
        'target': target,
        'window': window,
        'indicator': indicator,
        'latency_threshold': latencyThreshold,
        'template': template,
        'journey': journey,
        'error_query': errorQuery,
        'total_query': totalQuery,
      }),
    );
    return response.statusCode == 200;
  }

  /// Disables/deletes an SLO configuration for a service.
  static Future<bool> deleteSLO(String serviceId) async {
    final response = await http.delete(Uri.parse('/api/slo/$serviceId'));
    return response.statusCode == 200;
  }

  /// Fetches SLO notification configuration (Email, Webhook).
  static Future<Map<String, dynamic>> fetchSLONotifyConfig() async {
    final response = await http.get(Uri.parse('/api/slo/notify/config'));
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    return {};
  }

  /// Saves SLO notification configuration (Email, Webhook).
  static Future<bool> saveSLONotifyConfig(Map<String, dynamic> config) async {
    final response = await http.post(
      Uri.parse('/api/slo/notify/config'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(config),
    );
    return response.statusCode == 200;
  }

  /// Dispatches a test SLO alert notification (email or webhook).
  static Future<Map<String, dynamic>> testSLONotify(String channel) async {
    final response = await http.post(
      Uri.parse('/api/slo/notify/test'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'channel': channel}),
    );
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Fetches all deployed services from state.
  static Future<List<Service>> fetchServices() async {
    final state = await fetchState();
    return state.services;
  }

  /// Caddy: Fetches Caddy status and stats for a given node.
  static Future<Map<String, dynamic>> fetchCaddyStatus({String? nodeId}) async {
    final uri = Uri.parse('/api/caddy/status${nodeId != null ? '?node_id=$nodeId' : ''}');
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return {};
  }

  /// Caddy: Fetches dynamic routes matrix.
  static Future<List<dynamic>> fetchCaddyRoutes({String? nodeId}) async {
    final uri = Uri.parse('/api/caddy/routes${nodeId != null ? '?node_id=$nodeId' : ''}');
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['routes'] ?? [];
    }
    return [];
  }

  /// Caddy: Fetches TLS certs list.
  static Future<List<dynamic>> fetchCaddyCerts({String? nodeId}) async {
    final uri = Uri.parse('/api/caddy/certs${nodeId != null ? '?node_id=$nodeId' : ''}');
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['certificates'] ?? [];
    }
    return [];
  }

  /// Caddy: Fetches tail logs.
  static Future<List<String>> fetchCaddyLogs({String? nodeId}) async {
    final uri = Uri.parse('/api/caddy/logs${nodeId != null ? '?node_id=$nodeId' : ''}');
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final List raw = data['logs'] ?? [];
      return raw.map((e) => e.toString()).toList();
    }
    return [];
  }

  /// Caddy: Fetches Prometheus metrics.
  static Future<Map<String, dynamic>> fetchCaddyMetrics({String? nodeId}) async {
    final uri = Uri.parse('/api/caddy/metrics${nodeId != null ? '?node_id=$nodeId' : ''}');
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return {};
  }

  /// Caddy: Formats Caddyfile content via caddy fmt.
  static Future<String> formatCaddyfile(String caddyfile) async {
    final response = await http.post(
      Uri.parse('/api/caddy/fmt'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'caddyfile': caddyfile}),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['formatted'] ?? caddyfile;
    }
    return caddyfile;
  }

  /// Caddy: Inspects full X.509 certificate details for a domain.
  static Future<Map<String, dynamic>?> inspectCaddyCert(String domain, {String? nodeId}) async {
    final uri = Uri.parse('/api/caddy/certs/inspect?domain=${Uri.encodeComponent(domain)}${nodeId != null ? '&node_id=$nodeId' : ''}');
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['certificate'];
    }
    return null;
  }

  /// Caddy: Forces certificate renewal/rotation for a domain.
  static Future<Map<String, dynamic>> renewCaddyCert(String domain, {String? nodeId}) async {
    final uri = Uri.parse('/api/caddy/certs/renew${nodeId != null ? '?node_id=$nodeId' : ''}');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'domain': domain}),
    );
    return jsonDecode(response.body);
  }

  /// Caddy: Installs a custom TLS certificate and private key.
  static Future<Map<String, dynamic>> uploadCustomCaddyCert(
    String domain,
    String certPem,
    String keyPem, {
    String? nodeId,
  }) async {
    final uri = Uri.parse('/api/caddy/certs/custom${nodeId != null ? '?node_id=$nodeId' : ''}');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'domain': domain,
        'cert_pem': certPem,
        'key_pem': keyPem,
      }),
    );
    return jsonDecode(response.body);
  }

  /// Caddy: Prunes orphaned certificates no longer referenced in Caddyfile.
  static Future<Map<String, dynamic>> pruneOrphanedCaddyCerts({String? nodeId}) async {
    final uri = Uri.parse('/api/caddy/certs/orphaned${nodeId != null ? '?node_id=$nodeId' : ''}');
    final response = await http.delete(uri);
    return jsonDecode(response.body);
  }

  /// Caddy: Synchronizes all TLS certificates across all active cluster nodes.
  static Future<Map<String, dynamic>> syncCaddyCerts() async {
    final response = await http.post(Uri.parse('/api/caddy/certs/sync'));
    return jsonDecode(response.body);
  }
}



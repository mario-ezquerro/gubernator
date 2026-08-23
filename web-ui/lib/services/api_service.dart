import 'dart:convert';
import 'dart:html' as html;
import 'package:http/http.dart' as http;
import '../models/models.dart';

/// Service class to communicate with the Gubernator backend API.
class ApiService {
  static String? _authToken;

  static String? get authToken {
    if (_authToken != null && _authToken!.isNotEmpty) {
      return _authToken;
    }
    try {
      _authToken = html.window.localStorage['gbnt_token'];
    } catch (_) {}
    return _authToken;
  }

  static set authToken(String? token) {
    _authToken = token;
    try {
      if (token != null && token.isNotEmpty) {
        html.window.localStorage['gbnt_token'] = token;
      } else {
        html.window.localStorage.remove('gbnt_token');
      }
    } catch (_) {}
  }

  static Map<String, String> get authHeaders {
    final headers = <String, String>{'Content-Type': 'application/json'};
    final token = authToken;
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  /// Fetches the full dashboard state from the backend.
  static Future<DashboardState> fetchState() async {
    final response = await http.get(Uri.parse('/api/state'), headers: authHeaders);
    if (response.statusCode == 200) {
      return DashboardState.fromJson(jsonDecode(response.body));
    }
    throw Exception('Failed to fetch state: ${response.statusCode}');
  }

  /// Deletes a stack and stops all its containers.
  static Future<bool> deleteStack(String id) async {
    final response = await http.delete(Uri.parse('/api/stack/$id'), headers: authHeaders);
    return response.statusCode == 200;
  }

  /// Redeploys a stack.
  static Future<bool> redeployStack(String id) async {
    final response = await http.post(Uri.parse('/api/stack/$id/redeploy'), headers: authHeaders);
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
    final response = await http.post(
      Uri.parse('/api/scope/enable'),
      headers: authHeaders,
    );
    return response.statusCode == 200;
  }

  /// Disables Weave Scope container.
  static Future<bool> disableScope() async {
    final response = await http.post(
      Uri.parse('/api/scope/disable'),
      headers: authHeaders,
    );
    return response.statusCode == 200;
  }

  /// Updates and pulls latest Weave Scope container image from Docker Hub.
  static Future<Map<String, dynamic>> updateScopeImage() async {
    final response = await http.post(
      Uri.parse('/api/scope/update'),
      headers: authHeaders,
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return {'error': 'Failed to update Scope image'};
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
    final response = await http.post(Uri.parse('/api/caddy/certs/sync'), headers: authHeaders);
    return jsonDecode(response.body);
  }

  // ─────────────────────────────────────────────────────────────
  // Enterprise Authentication & Active Directory / LDAP APIs
  // ─────────────────────────────────────────────────────────────

  /// Fetches available identity providers (Local Admin + Active Directory/LDAP).
  static Future<List<AuthProvider>> fetchAuthProviders() async {
    final response = await http.get(Uri.parse('/api/auth/providers'));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return (data['providers'] as List? ?? [])
          .map((e) => AuthProvider.fromJson(e))
          .toList();
    }
    return [const AuthProvider(id: 'local', name: 'Local Administrator', type: 'local')];
  }

  /// Logs in against Local Admin or an Active Directory/LDAP provider.
  static Future<Map<String, dynamic>> login(
    String username,
    String password, {
    String? provider,
  }) async {
    final response = await http.post(
      Uri.parse('/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
        'provider': provider ?? 'local',
      }),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode == 200 && data['token'] != null) {
      authToken = data['token'];
      return {'success': true, 'user': UserSession.fromJson(data['user'])};
    }
    return {'success': false, 'error': data['error'] ?? 'Login failed (${response.statusCode})'};
  }

  /// Fetches the currently authenticated user profile and permissions.
  static Future<UserSession?> fetchMe() async {
    try {
      final response = await http.get(Uri.parse('/api/auth/me'), headers: authHeaders);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return UserSession.fromJson(data['user']);
      }
    } catch (_) {}
    return null;
  }

  /// Logs out the user and clears stored session tokens.
  static Future<void> logout() async {
    try {
      await http.post(Uri.parse('/api/auth/logout'), headers: authHeaders);
    } catch (_) {}
    authToken = null;
  }

  /// Fetches all configured LDAP / Active Directory servers (Admin only).
  static Future<List<LDAPConfig>> fetchLDAPConfigs() async {
    final response = await http.get(Uri.parse('/api/auth/ldap'), headers: authHeaders);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return (data['configs'] as List? ?? [])
          .map((e) => LDAPConfig.fromJson(e))
          .toList();
    }
    return [];
  }

  /// Creates or updates an LDAP / Active Directory configuration.
  static Future<Map<String, dynamic>> saveLDAPConfig(LDAPConfig config) async {
    final response = await http.post(
      Uri.parse('/api/auth/ldap'),
      headers: authHeaders,
      body: jsonEncode(config.toJson()),
    );
    return jsonDecode(response.body);
  }

  /// Deletes an LDAP / Active Directory configuration.
  static Future<bool> deleteLDAPConfig(String id) async {
    final response = await http.delete(Uri.parse('/api/auth/ldap/$id'), headers: authHeaders);
    return response.statusCode == 200;
  }

  /// Tests connectivity and optional user credentials against an LDAP configuration.
  static Future<LDAPTestResult> testLDAPConfig(
    LDAPConfig config, {
    String testUsername = '',
    String testPassword = '',
  }) async {
    final response = await http.post(
      Uri.parse('/api/auth/ldap/test'),
      headers: authHeaders,
      body: jsonEncode({
        'config': config.toJson(),
        'test_username': testUsername,
        'test_password': testPassword,
      }),
    );

    final data = jsonDecode(response.body);
    if (data['result'] != null) {
      return LDAPTestResult.fromJson(data['result']);
    }
    return LDAPTestResult(
      connected: false,
      tlsActive: false,
      bindSuccessful: false,
      userFound: false,
      message: data['error'] ?? 'Connection test failed',
      latencyMs: 0,
    );
  }

  /// Fetches all local user accounts.
  static Future<List<LocalUser>> fetchLocalUsers() async {
    final response = await http.get(Uri.parse("/api/security/users"), headers: authHeaders);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return (data["users"] as List? ?? [])
          .map((e) => LocalUser.fromJson(e))
          .toList();
    }
    return [];
  }

  /// Creates a new local user.
  static Future<Map<String, dynamic>> createLocalUser({
    required String username,
    required String password,
    required String displayName,
    required String email,
    required String role,
    required bool enabled,
  }) async {
    final response = await http.post(
      Uri.parse("/api/security/users"),
      headers: authHeaders,
      body: jsonEncode({
        "username": username,
        "password": password,
        "display_name": displayName,
        "email": email,
        "role": role,
        "enabled": enabled,
      }),
    );
    return jsonDecode(response.body);
  }

  /// Updates an existing local user.
  static Future<Map<String, dynamic>> updateLocalUser(LocalUser user) async {
    final response = await http.put(
      Uri.parse("/api/security/users/${user.id}"),
      headers: authHeaders,
      body: jsonEncode(user.toJson()),
    );
    return jsonDecode(response.body);
  }

  /// Resets a local user password.
  static Future<Map<String, dynamic>> resetLocalUserPassword(String id, String newPassword) async {
    final response = await http.post(
      Uri.parse("/api/security/users/$id/password"),
      headers: authHeaders,
      body: jsonEncode({"new_password": newPassword}),
    );
    return jsonDecode(response.body);
  }

  /// Deletes a local user account.
  static Future<bool> deleteLocalUser(String id) async {
    final response = await http.delete(Uri.parse("/api/security/users/$id"), headers: authHeaders);
    return response.statusCode == 200;
  }

  /// Fetches access and audit logs.
  static Future<List<AuditLog>> fetchAuditLogs({String provider = "", String action = ""}) async {
    var url = "/api/security/audit-logs";
    List<String> queryParams = [];
    if (provider.isNotEmpty) queryParams.add("provider=$provider");
    if (action.isNotEmpty) queryParams.add("action=$action");
    if (queryParams.isNotEmpty) {
      url += "?${queryParams.join("&")}";
    }
    final response = await http.get(Uri.parse(url), headers: authHeaders);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return (data["audit_logs"] as List? ?? [])
          .map((e) => AuditLog.fromJson(e))
          .toList();
    }
    return [];
  }

  /// Checks status and readiness of Loki aggregator.
  static Future<Map<String, dynamic>> fetchLokiStatus() async {
    try {
      final response = await http.get(Uri.parse("/api/logs/status"), headers: authHeaders);
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return {"active": false, "driver": "docker_fallback"};
  }

  /// Fetches available containers, nodes, stacks, and streams for Loki filters.
  static Future<LokiLabelsResponse> fetchLokiLogLabels() async {
    try {
      final response = await http.get(Uri.parse("/api/logs/labels"), headers: authHeaders);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return LokiLabelsResponse.fromJson(data);
      }
    } catch (_) {}
    return LokiLabelsResponse(containers: [], nodes: [], stacks: [], streams: [], levels: []);
  }

  /// Queries logs with multi-dimensional filtering.
  static Future<Map<String, dynamic>> queryLokiLogs({
    String query = "",
    String container = "",
    String node = "",
    String stack = "",
    String stream = "",
    String level = "",
    String timeRange = "1h",
    int limit = 200,
  }) async {
    try {
      List<String> params = [];
      if (query.isNotEmpty) params.add("query=${Uri.encodeQueryComponent(query)}");
      if (container.isNotEmpty) params.add("container=${Uri.encodeQueryComponent(container)}");
      if (node.isNotEmpty) params.add("node=${Uri.encodeQueryComponent(node)}");
      if (stack.isNotEmpty) params.add("stack=${Uri.encodeQueryComponent(stack)}");
      if (stream.isNotEmpty) params.add("stream=${Uri.encodeQueryComponent(stream)}");
      if (level.isNotEmpty) params.add("level=${Uri.encodeQueryComponent(level)}");
      params.add("range=$timeRange");
      params.add("limit=$limit");

      var url = "/api/logs/query";
      if (params.isNotEmpty) {
        url += "?${params.join("&")}";
      }

      final response = await http.get(Uri.parse(url), headers: authHeaders);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = (data["logs"] as List? ?? [])
            .map((e) => LokiLogEntry.fromJson(e))
            .toList();
        return {
          "status": data["status"] ?? "success",
          "driver": data["driver"] ?? "loki",
          "total": data["total"] ?? list.length,
          "logs": list,
        };
      }
    } catch (_) {}
    return {"status": "error", "driver": "none", "total": 0, "logs": <LokiLogEntry>[]};
  }

  // ── Storage & Backups API Methods ─────────────────────────────────

  /// Fetches all cluster persistent volumes, docker volumes, and bind mounts.
  static Future<List<StorageVolumeModel>> fetchStorageVolumes({String? targetNode}) async {
    final url = (targetNode != null && targetNode.isNotEmpty && targetNode != 'all')
        ? '/api/storage/volumes?node=${Uri.encodeQueryComponent(targetNode)}'
        : '/api/storage/volumes';
    final response = await http.get(Uri.parse(url), headers: authHeaders);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final list = (data['volumes'] as List? ?? [])
          .map((e) => StorageVolumeModel.fromJson(e))
          .toList();
      return list;
    }
    throw Exception('Failed to fetch storage volumes: ${response.statusCode}');
  }

  /// Creates a new Docker named volume on target nodes.
  static Future<String> createDockerVolume({
    required String name,
    required String targetNode,
    String driver = 'local',
    Map<String, String>? driverOpts,
    Map<String, String>? labels,
  }) async {
    final response = await http.post(
      Uri.parse('/api/storage/volumes/docker'),
      headers: authHeaders,
      body: jsonEncode({
        'name': name,
        'driver': driver,
        'target_node': targetNode,
        if (driverOpts != null && driverOpts.isNotEmpty) 'driver_opts': driverOpts,
        if (labels != null && labels.isNotEmpty) 'labels': labels,
      }),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['message'] ?? 'Volume created successfully';
    }
    final errData = jsonDecode(response.body);
    throw Exception(errData['error'] ?? 'Failed to create volume (${response.statusCode})');
  }

  /// Deletes a Docker volume from target node(s).
  static Future<String> deleteDockerVolume({
    required String name,
    String? targetNode,
    bool force = false,
  }) async {
    final queryParams = <String, String>{
      'name': name,
      if (targetNode != null && targetNode.isNotEmpty) 'node': targetNode,
      if (force) 'force': 'true',
    };
    final uri = Uri.parse('/api/storage/volumes/docker').replace(queryParameters: queryParams);
    final response = await http.delete(uri, headers: authHeaders);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['message'] ?? 'Volume deleted successfully';
    }
    final errData = jsonDecode(response.body);
    throw Exception(errData['error'] ?? 'Failed to delete volume (${response.statusCode})');
  }

  /// Prunes unused / dangling Docker volumes on target node(s).
  static Future<String> pruneDockerVolumes({String? targetNode}) async {
    final response = await http.post(
      Uri.parse('/api/storage/volumes/docker/prune'),
      headers: authHeaders,
      body: jsonEncode({
        'target_node': targetNode ?? 'all',
      }),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['report'] ?? data['message'] ?? 'Pruned successfully';
    }
    final errData = jsonDecode(response.body);
    throw Exception(errData['error'] ?? 'Failed to prune volumes (${response.statusCode})');
  }

  /// Inspects a Docker volume and returns JSON metadata.
  static Future<Map<String, dynamic>> inspectDockerVolume({
    required String name,
    String? targetNode,
  }) async {
    final queryParams = <String, String>{
      'name': name,
      if (targetNode != null && targetNode.isNotEmpty) 'node': targetNode,
    };
    final uri = Uri.parse('/api/storage/volumes/docker/inspect').replace(queryParameters: queryParams);
    final response = await http.get(uri, headers: authHeaders);
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    final errData = jsonDecode(response.body);
    throw Exception(errData['error'] ?? 'Failed to inspect volume (${response.statusCode})');
  }

  /// Creates a new storage directory on target nodes.
  static Future<bool> createStorageDirectory({
    required String path,
    required String targetNode,
    String permissions = '0777',
  }) async {
    final response = await http.post(
      Uri.parse('/api/storage/directories'),
      headers: authHeaders,
      body: jsonEncode({
        'path': path,
        'target_node': targetNode,
        'permissions': permissions,
      }),
    );
    return response.statusCode == 200;
  }

  /// Lists files and subdirectories within a given path on a specific node.
  static Future<List<DirectoryEntryModel>> listDirectoryContents({
    required String path,
    String? targetNode,
  }) async {
    final queryParams = <String, String>{'path': path};
    if (targetNode != null && targetNode.isNotEmpty) {
      queryParams['node'] = targetNode;
    }
    final uri = Uri.parse('/api/storage/directories/ls').replace(queryParameters: queryParams);
    final response = await http.get(uri, headers: authHeaders);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return (data['entries'] as List? ?? [])
          .map((e) => DirectoryEntryModel.fromJson(e))
          .toList();
    }
    throw Exception('Failed to list directory contents: ${response.statusCode}');
  }

  /// Fetches shared storage pool health and capacity diagnostics.
  static Future<PoolHealthModel> fetchStoragePoolHealth({String path = '/var/contenedores'}) async {
    final url = '/api/storage/pools/health?path=${Uri.encodeQueryComponent(path)}';
    final response = await http.get(Uri.parse(url), headers: authHeaders);
    if (response.statusCode == 200) {
      return PoolHealthModel.fromJson(jsonDecode(response.body));
    }
    throw Exception('Failed to fetch storage pool health: ${response.statusCode}');
  }

  /// Fetches all backup archives.
  static Future<List<BackupModel>> fetchBackups() async {
    final response = await http.get(Uri.parse('/api/backups'), headers: authHeaders);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final list = (data['backups'] as List? ?? [])
          .map((e) => BackupModel.fromJson(e))
          .toList();
      return list;
    }
    throw Exception('Failed to fetch backups: ${response.statusCode}');
  }

  /// Creates a new compressed backup archive.
  static Future<BackupModel> createBackup({
    required String name,
    String stackId = '',
    String volumeName = '',
    String sourcePath = '',
    String destinationPath = '',
    bool pauseContainers = true,
  }) async {
    final body = jsonEncode({
      'name': name,
      'stack_id': stackId,
      'volume_name': volumeName,
      'source_path': sourcePath,
      'destination_path': destinationPath,
      'pause_containers': pauseContainers,
    });
    final response = await http.post(
      Uri.parse('/api/backups/create'),
      headers: authHeaders,
      body: body,
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return BackupModel.fromJson(data['backup']);
    }
    final errData = jsonDecode(response.body);
    throw Exception(errData['error'] ?? 'Failed to create backup');
  }

  /// Restores a backup archive to target directory.
  static Future<bool> restoreBackup({
    required String backupId,
    String targetPath = '',
  }) async {
    final body = jsonEncode({
      'backup_id': backupId,
      'target_path': targetPath,
    });
    final response = await http.post(
      Uri.parse('/api/backups/restore'),
      headers: authHeaders,
      body: body,
    );
    if (response.statusCode == 200) {
      return true;
    }
    final errData = jsonDecode(response.body);
    throw Exception(errData['error'] ?? 'Failed to restore backup');
  }

  /// Deletes a backup archive.
  static Future<bool> deleteBackup(String id) async {
    final response = await http.delete(Uri.parse('/api/backups/$id'), headers: authHeaders);
    return response.statusCode == 200;
  }

  /// Fetches all automated backup schedules.
  static Future<List<BackupScheduleModel>> fetchBackupSchedules() async {
    final response = await http.get(Uri.parse('/api/backups/schedules'), headers: authHeaders);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final list = (data['schedules'] as List? ?? [])
          .map((e) => BackupScheduleModel.fromJson(e))
          .toList();
      return list;
    }
    throw Exception('Failed to fetch backup schedules: ${response.statusCode}');
  }

  /// Creates or updates a backup schedule.
  static Future<BackupScheduleModel> saveBackupSchedule(BackupScheduleModel schedule) async {
    final response = await http.post(
      Uri.parse('/api/backups/schedules'),
      headers: authHeaders,
      body: jsonEncode(schedule.toJson()),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return BackupScheduleModel.fromJson(data['schedule']);
    }
    final errData = jsonDecode(response.body);
    throw Exception(errData['error'] ?? 'Failed to save schedule');
  }

  /// Deletes a backup schedule.
  static Future<bool> deleteBackupSchedule(String id) async {
    final response = await http.delete(Uri.parse('/api/backups/schedules/$id'), headers: authHeaders);
    return response.statusCode == 200;
  }

  /// Fetches all network storage mounts (NFS, S3, Samba, /etc/fstab).
  static Future<List<StorageMountModel>> fetchStorageMounts() async {
    final response = await http.get(Uri.parse('/api/storage/mounts'), headers: authHeaders);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final list = (data['mounts'] as List? ?? [])
          .map((e) => StorageMountModel.fromJson(e))
          .toList();
      return list;
    }
    throw Exception('Failed to fetch mounts: ${response.statusCode}');
  }

  /// Creates and mounts a new network storage entry.
  static Future<StorageMountModel> createStorageMount(Map<String, dynamic> req) async {
    final response = await http.post(
      Uri.parse('/api/storage/mounts'),
      headers: authHeaders,
      body: jsonEncode(req),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return StorageMountModel.fromJson(data['mount']);
    }
    final errData = jsonDecode(response.body);
    throw Exception(errData['error'] ?? 'Failed to configure mount');
  }

  /// Tests connectivity and R/W access for a remote mount.
  static Future<TestMountResultModel> testStorageMount(Map<String, dynamic> req) async {
    final response = await http.post(
      Uri.parse('/api/storage/mounts/test'),
      headers: authHeaders,
      body: jsonEncode(req),
    );
    if (response.statusCode == 200) {
      return TestMountResultModel.fromJson(jsonDecode(response.body));
    }
    final errData = jsonDecode(response.body);
    throw Exception(errData['error'] ?? 'Failed to test mount');
  }

  /// Mounts an existing configured entry on target node(s).
  static Future<bool> mountStorageEntry(String id, {String? targetNode}) async {
    final body = targetNode != null && targetNode.isNotEmpty ? jsonEncode({'target_node': targetNode}) : null;
    final response = await http.post(
      Uri.parse('/api/storage/mounts/$id/mount'),
      headers: authHeaders,
      body: body,
    );
    if (response.statusCode == 200) return true;
    final errData = jsonDecode(response.body);
    throw Exception(errData['error'] ?? 'Mount failed');
  }

  /// Unmounts an existing entry from target node(s).
  static Future<bool> unmountStorageEntry(String id, {String? targetNode}) async {
    final body = targetNode != null && targetNode.isNotEmpty ? jsonEncode({'target_node': targetNode}) : null;
    final response = await http.post(
      Uri.parse('/api/storage/mounts/$id/unmount'),
      headers: authHeaders,
      body: body,
    );
    if (response.statusCode == 200) return true;
    final errData = jsonDecode(response.body);
    throw Exception(errData['error'] ?? 'Unmount failed');
  }

  /// Deletes a mount and cleans up /etc/fstab across target nodes.
  /// If deleteGluster is true, also deletes the underlying GlusterFS volume.
  static Future<bool> deleteStorageMount(String id, {bool deleteGluster = false}) async {
    final url = deleteGluster ? '/api/storage/mounts/$id?delete_gluster=true' : '/api/storage/mounts/$id';
    final response = await http.delete(Uri.parse(url), headers: authHeaders);
    return response.statusCode == 200;
  }

  /// Executes mount -a on host or all cluster nodes.
  static Future<String> mountAllStorageEntries({String? targetNode}) async {
    final body = targetNode != null && targetNode.isNotEmpty ? jsonEncode({'target_node': targetNode}) : null;
    final response = await http.post(
      Uri.parse('/api/storage/mounts/mount-all'),
      headers: authHeaders,
      body: body,
    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return data['output'] ?? 'OK';
    }
    throw Exception(data['error'] ?? 'mount -a failed');
  }

  /// Fetches raw /etc/fstab contents from a specific host or local manager.
  static Future<Map<String, dynamic>> fetchRawFstab({String? node}) async {
    final query = (node != null && node.isNotEmpty) ? '?node=$node' : '';
    final response = await http.get(Uri.parse('/api/storage/fstab/raw$query'), headers: authHeaders);
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to read fstab: ${response.statusCode}');
  }

  /// Saves and safely writes raw /etc/fstab on target node(s) with automated backup.
  static Future<String> saveRawFstab(String content, {String? node}) async {
    final response = await http.post(
      Uri.parse('/api/storage/fstab/raw'),
      headers: authHeaders,
      body: jsonEncode({
        'node': node ?? 'all',
        'content': content,
      }),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return data['message'] ?? 'fstab saved successfully';
    }
    throw Exception(data['error'] ?? 'Failed to save /etc/fstab');
  }

  // ── Image Security & SBOM API Methods ──────────────────────────────────────

  /// Fetches all image vulnerability scans and cluster security summary.
  static Future<Map<String, dynamic>> fetchImageScans() async {
    final response = await http.get(Uri.parse('/api/security/scans'), headers: authHeaders);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final scans = (data['scans'] as List? ?? [])
          .map((e) => ImageScanModel.fromJson(e))
          .toList();
      final summary = data['summary'] != null ? SecuritySummaryModel.fromJson(data['summary']) : SecuritySummaryModel();
      return {
        'scans': scans,
        'summary': summary,
      };
    }
    throw Exception('Failed to fetch security scans: ${response.statusCode}');
  }

  /// Fetches details and CVEs for a specific scan ID.
  static Future<Map<String, dynamic>> fetchScanDetails(String scanId) async {
    final response = await http.get(Uri.parse('/api/security/scans/$scanId'), headers: authHeaders);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final scan = ImageScanModel.fromJson(data['scan']);
      final vulns = (data['vulnerabilities'] as List? ?? [])
          .map((e) => ImageVulnerabilityModel.fromJson(e))
          .toList();
      return {
        'scan': scan,
        'vulnerabilities': vulns,
      };
    }
    throw Exception('Failed to fetch scan details: ${response.statusCode}');
  }

  /// Triggers an immediate vulnerability scan for an image.
  static Future<Map<String, dynamic>> triggerImageScan(String image) async {
    final response = await http.post(
      Uri.parse('/api/security/scans/trigger'),
      headers: authHeaders,
      body: jsonEncode({'image': image}),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return {
        'scan': ImageScanModel.fromJson(data['scan']),
        'vulnerabilities': (data['vulnerabilities'] as List? ?? [])
            .map((e) => ImageVulnerabilityModel.fromJson(e))
            .toList(),
      };
    }
    final err = jsonDecode(response.body);
    throw Exception(err['error'] ?? 'Scan failed');
  }

  /// Forces a complete re-scan and sync of all cluster images across all hosts.
  static Future<Map<String, dynamic>> syncAllImageScans() async {
    final response = await http.post(
      Uri.parse('/api/security/scans/sync-all'),
      headers: authHeaders,
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final scans = (data['scans'] as List? ?? [])
          .map((e) => ImageScanModel.fromJson(e))
          .toList();
      final summary = data['summary'] != null ? SecuritySummaryModel.fromJson(data['summary']) : SecuritySummaryModel();
      return {
        'scans': scans,
        'summary': summary,
      };
    }
    final err = jsonDecode(response.body);
    throw Exception(err['error'] ?? 'Sync failed');
  }

  /// Fetches trusted public signing keys.
  static Future<List<TrustedKeyModel>> fetchTrustedKeys() async {
    final response = await http.get(Uri.parse('/api/security/keys'), headers: authHeaders);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final list = (data['keys'] as List? ?? [])
          .map((e) => TrustedKeyModel.fromJson(e))
          .toList();
      return list;
    }
    throw Exception('Failed to fetch trusted keys: ${response.statusCode}');
  }

  /// Generates a new Cosign ECDSA keypair.
  static Future<Map<String, dynamic>> generateTrustedKey(String name, {bool isDefault = false}) async {
    final response = await http.post(
      Uri.parse('/api/security/keys/generate'),
      headers: authHeaders,
      body: jsonEncode({'name': name, 'is_default': isDefault}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    final err = jsonDecode(response.body);
    throw Exception(err['error'] ?? 'Keypair generation failed');
  }

  /// Saves or imports an existing public key.
  static Future<TrustedKeyModel> saveTrustedKey(String name, String pubPEM, {bool isDefault = false}) async {
    final response = await http.post(
      Uri.parse('/api/security/keys'),
      headers: authHeaders,
      body: jsonEncode({'name': name, 'public_key_pem': pubPEM, 'is_default': isDefault}),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return TrustedKeyModel.fromJson(data['key']);
    }
    final err = jsonDecode(response.body);
    throw Exception(err['error'] ?? 'Failed to import key');
  }

  /// Deletes a trusted signing key.
  static Future<bool> deleteTrustedKey(String id) async {
    final response = await http.delete(Uri.parse('/api/security/keys/$id'), headers: authHeaders);
    return response.statusCode == 200;
  }

  /// Signs an image with a private key.
  static Future<Map<String, dynamic>> signImage(String image, String privateKey, {String signerName = 'Cluster Admin'}) async {
    final response = await http.post(
      Uri.parse('/api/security/sign'),
      headers: authHeaders,
      body: jsonEncode({
        'image': image,
        'private_key': privateKey,
        'signer_name': signerName,
      }),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    final err = jsonDecode(response.body);
    throw Exception(err['error'] ?? 'Image signing failed');
  }

  /// Fetches cluster admission security policy.
  static Future<SecurityPolicyModel> fetchSecurityPolicy() async {
    final response = await http.get(Uri.parse('/api/security/policy'), headers: authHeaders);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return SecurityPolicyModel.fromJson(data['policy']);
    }
    throw Exception('Failed to fetch security policy: ${response.statusCode}');
  }

  /// Saves cluster admission security policy.
  static Future<SecurityPolicyModel> saveSecurityPolicy(SecurityPolicyModel policy) async {
    final response = await http.post(
      Uri.parse('/api/security/policy'),
      headers: authHeaders,
      body: jsonEncode(policy.toJson()),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return SecurityPolicyModel.fromJson(data['policy']);
    }
    final err = jsonDecode(response.body);
    throw Exception(err['error'] ?? 'Failed to update policy');
  }

  /// Fetches transparent GitHub adoption stats & release metrics.
  static Future<AdoptionStatsModel> fetchAdoptionStats({bool force = false}) async {
    final url = force ? '/api/system/adoption?force=true' : '/api/system/adoption';
    final response = await http.get(Uri.parse(url), headers: authHeaders);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return AdoptionStatsModel.fromJson(data);
    }
    throw Exception('Failed to fetch adoption stats: ${response.statusCode}');
  }

  // ─── GlusterFS Cluster Storage Services ───────────────────────────────────

  /// Fetches all peers in the GlusterFS trusted storage pool.
  static Future<List<GlusterPeerModel>> fetchGlusterPeers() async {
    final response = await http.get(Uri.parse('/api/storage/gluster/peers'), headers: authHeaders);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['peers'] is List) {
        return (data['peers'] as List).map((p) => GlusterPeerModel.fromJson(p)).toList();
      }
      return [];
    }
    throw Exception('Failed to fetch GlusterFS peers: ${response.statusCode}');
  }

  /// Probes a new node into the trusted storage pool.
  static Future<void> probeGlusterPeer(String hostname) async {
    final response = await http.post(
      Uri.parse('/api/storage/gluster/peers/probe'),
      headers: authHeaders,
      body: jsonEncode({'hostname': hostname}),
    );
    if (response.statusCode != 200) {
      final err = jsonDecode(response.body);
      throw Exception(err['error'] ?? 'Failed to probe peer $hostname');
    }
  }

  /// Detaches a peer from the trusted storage pool.
  static Future<void> detachGlusterPeer(String hostname, {bool force = false}) async {
    final url = force ? '/api/storage/gluster/peers/$hostname?force=true' : '/api/storage/gluster/peers/$hostname';
    final response = await http.delete(Uri.parse(url), headers: authHeaders);
    if (response.statusCode != 200) {
      final err = jsonDecode(response.body);
      throw Exception(err['error'] ?? 'Failed to detach peer $hostname');
    }
  }

  /// Fetches all GlusterFS volumes.
  static Future<List<GlusterVolumeModel>> fetchGlusterVolumes() async {
    final response = await http.get(Uri.parse('/api/storage/gluster/volumes'), headers: authHeaders);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['volumes'] is List) {
        return (data['volumes'] as List).map((v) => GlusterVolumeModel.fromJson(v)).toList();
      }
      return [];
    }
    throw Exception('Failed to fetch GlusterFS volumes: ${response.statusCode}');
  }

  /// Creates and tunes a new GlusterFS volume.
  static Future<void> createGlusterVolume(Map<String, dynamic> payload) async {
    final response = await http.post(
      Uri.parse('/api/storage/gluster/volumes'),
      headers: authHeaders,
      body: jsonEncode(payload),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      final err = jsonDecode(response.body);
      throw Exception(err['error'] ?? 'Failed to create GlusterFS volume');
    }
  }

  /// Deletes a GlusterFS volume and optionally unmounts from /etc/fstab across cluster nodes.
  static Future<void> deleteGlusterVolume(String name, {bool unmount = true}) async {
    final url = unmount ? '/api/storage/gluster/volumes/$name?unmount=true' : '/api/storage/gluster/volumes/$name?unmount=false';
    final response = await http.delete(Uri.parse(url), headers: authHeaders);
    if (response.statusCode != 200) {
      final err = jsonDecode(response.body);
      throw Exception(err['error'] ?? 'Failed to delete volume $name');
    }
  }

  /// Deletes all GlusterFS volumes across the cluster.
  static Future<void> deleteAllGlusterVolumes({bool unmount = true}) async {
    final url = unmount ? '/api/storage/gluster/volumes/delete-all?unmount=true' : '/api/storage/gluster/volumes/delete-all?unmount=false';
    final response = await http.post(Uri.parse(url), headers: authHeaders);
    if (response.statusCode != 200) {
      final err = jsonDecode(response.body);
      throw Exception(err['error'] ?? 'Failed to delete all GlusterFS volumes');
    }
  }

  /// Starts a GlusterFS volume.
  static Future<void> startGlusterVolume(String name) async {
    final response = await http.post(Uri.parse('/api/storage/gluster/volumes/$name/start'), headers: authHeaders);
    if (response.statusCode != 200) {
      final err = jsonDecode(response.body);
      throw Exception(err['error'] ?? 'Failed to start volume $name');
    }
  }

  /// Stops a GlusterFS volume.
  static Future<void> stopGlusterVolume(String name, {bool force = false}) async {
    final url = force ? '/api/storage/gluster/volumes/$name/stop?force=true' : '/api/storage/gluster/volumes/$name/stop';
    final response = await http.post(Uri.parse(url), headers: authHeaders);
    if (response.statusCode != 200) {
      final err = jsonDecode(response.body);
      throw Exception(err['error'] ?? 'Failed to stop volume $name');
    }
  }

  /// Fetches self-healing & split-brain diagnostics for a volume.
  static Future<GlusterHealModel> fetchGlusterHealReport(String name) async {
    final response = await http.get(Uri.parse('/api/storage/gluster/volumes/$name/heal'), headers: authHeaders);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return GlusterHealModel.fromJson(data['heal_report']);
    }
    throw Exception('Failed to fetch heal report: ${response.statusCode}');
  }

  /// Triggers a manual self-heal cycle.
  static Future<void> triggerGlusterSelfHeal(String name) async {
    final response = await http.post(Uri.parse('/api/storage/gluster/volumes/$name/heal'), headers: authHeaders);
    if (response.statusCode != 200) {
      final err = jsonDecode(response.body);
      throw Exception(err['error'] ?? 'Failed to trigger self-heal for $name');
    }
  }

  /// Auto-mounts volume to /var/contenedores across cluster hosts or specific target nodes.
  static Future<void> mountGlusterCluster(String name, {String mountPoint = '/var/contenedores', List<String>? targetNodes}) async {
    final payload = <String, dynamic>{'mount_point': mountPoint};
    if (targetNodes != null && targetNodes.isNotEmpty) {
      payload['target_nodes'] = targetNodes;
    }
    final response = await http.post(
      Uri.parse('/api/storage/gluster/volumes/$name/mount-cluster'),
      headers: authHeaders,
      body: jsonEncode(payload),
    );
    if (response.statusCode != 200) {
      final err = jsonDecode(response.body);
      throw Exception(err['error'] ?? 'Failed to mount volume $name across cluster');
    }
  }

  /// Fetches cluster diagnostics for GlusterFS.
  static Future<GlusterClusterDiagnosticsModel> fetchGlusterDiagnostics() async {
    final response = await http.get(Uri.parse('/api/storage/gluster/diagnostics'), headers: authHeaders);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return GlusterClusterDiagnosticsModel.fromJson(data['diagnostics']);
    }
    throw Exception('Failed to fetch Gluster diagnostics: ${response.statusCode}');
  }

  /// Fetches real-time dedicated storage network traffic and interface discovery.
  static Future<StorageNetworkReportModel> fetchStorageNetworkReport() async {
    final response = await http.get(Uri.parse('/api/storage/gluster/network'), headers: authHeaders);
    if (response.statusCode == 200) {
      return StorageNetworkReportModel.fromJson(jsonDecode(response.body));
    }
    throw Exception('Failed to fetch storage network report: ${response.statusCode}');
  }

  /// Fetches real-time I/O performance and FOP profiling for a volume.
  static Future<GlusterProfileReportModel> fetchGlusterVolumeProfile(String name) async {
    final response = await http.get(Uri.parse('/api/storage/gluster/volumes/$name/profile'), headers: authHeaders);
    if (response.statusCode == 200) {
      return GlusterProfileReportModel.fromJson(jsonDecode(response.body));
    }
    throw Exception('Failed to fetch profile for $name: ${response.statusCode}');
  }

  /// Starts volume profiling.
  static Future<void> startGlusterVolumeProfile(String name) async {
    final response = await http.post(Uri.parse('/api/storage/gluster/volumes/$name/profile/start'), headers: authHeaders);
    if (response.statusCode != 200) {
      final err = jsonDecode(response.body);
      throw Exception(err['error'] ?? 'Failed to start profiling on $name');
    }
  }

  /// Stops volume profiling.
  static Future<void> stopGlusterVolumeProfile(String name) async {
    final response = await http.post(Uri.parse('/api/storage/gluster/volumes/$name/profile/stop'), headers: authHeaders);
    if (response.statusCode != 200) {
      final err = jsonDecode(response.body);
      throw Exception(err['error'] ?? 'Failed to stop profiling on $name');
    }
  }

  /// Fetches directory path quotas for a volume.
  static Future<GlusterQuotasReportModel> fetchGlusterQuotas(String name) async {
    final response = await http.get(Uri.parse('/api/storage/gluster/volumes/$name/quotas'), headers: authHeaders);
    if (response.statusCode == 200) {
      return GlusterQuotasReportModel.fromJson(jsonDecode(response.body));
    }
    throw Exception('Failed to fetch quotas for $name: ${response.statusCode}');
  }

  /// Sets or updates a directory quota limit on a volume.
  static Future<void> setGlusterQuota(String name, String path, String hardLimit) async {
    final response = await http.post(
      Uri.parse('/api/storage/gluster/volumes/$name/quotas'),
      headers: authHeaders,
      body: jsonEncode({'path': path, 'hard_limit': hardLimit}),
    );
    if (response.statusCode != 200) {
      final err = jsonDecode(response.body);
      throw Exception(err['error'] ?? 'Failed to set quota on $name');
    }
  }

  /// Disables quotas on a volume.
  static Future<void> disableGlusterQuota(String name) async {
    final response = await http.delete(Uri.parse('/api/storage/gluster/volumes/$name/quotas'), headers: authHeaders);
    if (response.statusCode != 200) {
      final err = jsonDecode(response.body);
      throw Exception(err['error'] ?? 'Failed to disable quotas on $name');
    }
  }

  /// Fetches volume snapshots.
  static Future<List<GlusterSnapshotModel>> fetchGlusterSnapshots({String? volumeName}) async {
    final url = volumeName != null && volumeName.isNotEmpty
        ? '/api/storage/gluster/snapshots?volume=$volumeName'
        : '/api/storage/gluster/snapshots';
    final response = await http.get(Uri.parse(url), headers: authHeaders);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['snapshots'] is List) {
        return (data['snapshots'] as List).map((s) => GlusterSnapshotModel.fromJson(s)).toList();
      }
      return [];
    }
    throw Exception('Failed to fetch snapshots: ${response.statusCode}');
  }

  /// Creates a point-in-time snapshot.
  static Future<void> createGlusterSnapshot(String name, String volumeName, {String description = ''}) async {
    final response = await http.post(
      Uri.parse('/api/storage/gluster/snapshots'),
      headers: authHeaders,
      body: jsonEncode({'name': name, 'volume_name': volumeName, 'description': description}),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      final err = jsonDecode(response.body);
      throw Exception(err['error'] ?? 'Failed to create snapshot');
    }
  }

  /// Restores a snapshot (rollback).
  static Future<void> restoreGlusterSnapshot(String name) async {
    final response = await http.post(Uri.parse('/api/storage/gluster/snapshots/$name/restore'), headers: authHeaders);
    if (response.statusCode != 200) {
      final err = jsonDecode(response.body);
      throw Exception(err['error'] ?? 'Failed to restore snapshot $name');
    }
  }

  /// Deletes a snapshot.
  static Future<void> deleteGlusterSnapshot(String name) async {
    final response = await http.delete(Uri.parse('/api/storage/gluster/snapshots/$name'), headers: authHeaders);
    if (response.statusCode != 200) {
      final err = jsonDecode(response.body);
      throw Exception(err['error'] ?? 'Failed to delete snapshot $name');
    }
  }

  /// Starts or stops volume rebalance.
  static Future<Map<String, dynamic>> rebalanceGlusterVolume(String name, {String action = 'start'}) async {
    final response = await http.post(
      Uri.parse('/api/storage/gluster/volumes/$name/rebalance?action=$action'),
      headers: authHeaders,
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    final err = jsonDecode(response.body);
    throw Exception(err['error'] ?? 'Failed to rebalance $name');
  }

  /// Sets or resets an advanced volume tuning option.
  static Future<void> setGlusterVolumeOption(String name, String key, String value, {bool reset = false}) async {
    final response = await http.post(
      Uri.parse('/api/storage/gluster/volumes/$name/options'),
      headers: authHeaders,
      body: jsonEncode({'key': key, 'value': value, 'reset': reset}),
    );
    if (response.statusCode != 200) {
      final err = jsonDecode(response.body);
      throw Exception(err['error'] ?? 'Failed to configure option on $name');
    }
  }
}

// -----------------------------------------------------------------------------
// Cockpit-Storaged & Storage Network Models
// -----------------------------------------------------------------------------

class StorageNetworkReportModel {
  final String dedicatedSubnet;
  final String corednsSuffix;
  final List<NodeStorageNetworkModel> nodes;
  final double totalRxRateMBs;
  final double totalTxRateMBs;
  final bool activeTraffic;

  StorageNetworkReportModel({
    required this.dedicatedSubnet,
    required this.corednsSuffix,
    required this.nodes,
    required this.totalRxRateMBs,
    required this.totalTxRateMBs,
    required this.activeTraffic,
  });

  factory StorageNetworkReportModel.fromJson(Map<String, dynamic> json) {
    var nodesList = <NodeStorageNetworkModel>[];
    if (json['nodes'] is List) {
      nodesList = (json['nodes'] as List).map((n) => NodeStorageNetworkModel.fromJson(n)).toList();
    }
    return StorageNetworkReportModel(
      dedicatedSubnet: json['dedicated_subnet'] ?? '10.10.100.0/24',
      corednsSuffix: json['coredns_suffix'] ?? '.storage.gbnt.local',
      nodes: nodesList,
      totalRxRateMBs: (json['total_rx_rate_mbs'] as num?)?.toDouble() ?? 0.0,
      totalTxRateMBs: (json['total_tx_rate_mbs'] as num?)?.toDouble() ?? 0.0,
      activeTraffic: json['active_traffic'] ?? false,
    );
  }

  factory StorageNetworkReportModel.empty() {
    return StorageNetworkReportModel(
      dedicatedSubnet: '10.10.100.0/24',
      corednsSuffix: '.storage.gbnt.local',
      nodes: [],
      totalRxRateMBs: 0.0,
      totalTxRateMBs: 0.0,
      activeTraffic: false,
    );
  }
}

class NodeStorageNetworkModel {
  final String nodeId;
  final String nodeRole;
  final String hostIp;
  final String storageIp;
  final String storageDns;
  final String storageNic;
  final List<StorageNetworkInterfaceModel> interfaces;
  final bool isOnline;

  NodeStorageNetworkModel({
    required this.nodeId,
    required this.nodeRole,
    required this.hostIp,
    required this.storageIp,
    required this.storageDns,
    required this.storageNic,
    required this.interfaces,
    required this.isOnline,
  });

  factory NodeStorageNetworkModel.fromJson(Map<String, dynamic> json) {
    var ifaces = <StorageNetworkInterfaceModel>[];
    if (json['interfaces'] is List) {
      ifaces = (json['interfaces'] as List).map((i) => StorageNetworkInterfaceModel.fromJson(i)).toList();
    }
    return NodeStorageNetworkModel(
      nodeId: json['node_id'] ?? '',
      nodeRole: json['node_role'] ?? 'worker',
      hostIp: json['host_ip'] ?? '',
      storageIp: json['storage_ip'] ?? '',
      storageDns: json['storage_dns'] ?? '',
      storageNic: json['storage_nic'] ?? 'enp0s2',
      interfaces: ifaces,
      isOnline: json['is_online'] ?? true,
    );
  }
}

class StorageNetworkInterfaceModel {
  final String name;
  final List<String> ipAddresses;
  final String mac;
  final int mtu;
  final bool isUp;
  final bool isStorage;
  final double rxRateMBs;
  final double txRateMBs;
  final int rxBytes;
  final int txBytes;

  StorageNetworkInterfaceModel({
    required this.name,
    required this.ipAddresses,
    required this.mac,
    required this.mtu,
    required this.isUp,
    required this.isStorage,
    required this.rxRateMBs,
    required this.txRateMBs,
    required this.rxBytes,
    required this.txBytes,
  });

  factory StorageNetworkInterfaceModel.fromJson(Map<String, dynamic> json) {
    var ips = <String>[];
    if (json['ip_addresses'] is List) {
      ips = (json['ip_addresses'] as List).map((e) => e.toString()).toList();
    }
    return StorageNetworkInterfaceModel(
      name: json['name'] ?? '',
      ipAddresses: ips,
      mac: json['mac'] ?? '',
      mtu: json['mtu'] ?? 1500,
      isUp: json['is_up'] ?? false,
      isStorage: json['is_storage'] ?? false,
      rxRateMBs: (json['rx_rate_mbs'] as num?)?.toDouble() ?? 0.0,
      txRateMBs: (json['tx_rate_mbs'] as num?)?.toDouble() ?? 0.0,
      rxBytes: json['rx_bytes'] ?? 0,
      txBytes: json['tx_bytes'] ?? 0,
    );
  }
}

class GlusterProfileReportModel {
  final String volumeName;
  final bool isProfiling;
  final int totalIOPS;
  final double totalReadMBs;
  final double totalWriteMBs;
  final double avgLatencyMs;
  final List<ProfileFopModel> topOperations;
  final List<BlockSizeModel> blockSizeProfile;

  GlusterProfileReportModel({
    required this.volumeName,
    required this.isProfiling,
    required this.totalIOPS,
    required this.totalReadMBs,
    required this.totalWriteMBs,
    required this.avgLatencyMs,
    required this.topOperations,
    required this.blockSizeProfile,
  });

  factory GlusterProfileReportModel.fromJson(Map<String, dynamic> json) {
    var fops = <ProfileFopModel>[];
    if (json['top_operations'] is List) {
      fops = (json['top_operations'] as List).map((f) => ProfileFopModel.fromJson(f)).toList();
    }
    var blocks = <BlockSizeModel>[];
    if (json['block_size_profile'] is List) {
      blocks = (json['block_size_profile'] as List).map((b) => BlockSizeModel.fromJson(b)).toList();
    }
    return GlusterProfileReportModel(
      volumeName: json['volume_name'] ?? '',
      isProfiling: json['is_profiling'] ?? false,
      totalIOPS: json['total_iops'] ?? 0,
      totalReadMBs: (json['total_read_mbs'] as num?)?.toDouble() ?? 0.0,
      totalWriteMBs: (json['total_write_mbs'] as num?)?.toDouble() ?? 0.0,
      avgLatencyMs: (json['avg_latency_ms'] as num?)?.toDouble() ?? 0.0,
      topOperations: fops,
      blockSizeProfile: blocks,
    );
  }

  factory GlusterProfileReportModel.empty(String name) {
    return GlusterProfileReportModel(
      volumeName: name,
      isProfiling: false,
      totalIOPS: 0,
      totalReadMBs: 0.0,
      totalWriteMBs: 0.0,
      avgLatencyMs: 0.0,
      topOperations: [],
      blockSizeProfile: [],
    );
  }
}

class ProfileFopModel {
  final String operation;
  final int hits;
  final double percentage;
  final double avgLatencyUs;
  final double maxLatencyUs;

  ProfileFopModel({
    required this.operation,
    required this.hits,
    required this.percentage,
    required this.avgLatencyUs,
    required this.maxLatencyUs,
  });

  factory ProfileFopModel.fromJson(Map<String, dynamic> json) {
    return ProfileFopModel(
      operation: json['operation'] ?? '',
      hits: json['hits'] ?? 0,
      percentage: (json['percentage'] as num?)?.toDouble() ?? 0.0,
      avgLatencyUs: (json['avg_latency_us'] as num?)?.toDouble() ?? 0.0,
      maxLatencyUs: (json['max_latency_us'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class BlockSizeModel {
  final String range;
  final int readHits;
  final int writeHits;
  final double percentage;

  BlockSizeModel({
    required this.range,
    required this.readHits,
    required this.writeHits,
    required this.percentage,
  });

  factory BlockSizeModel.fromJson(Map<String, dynamic> json) {
    return BlockSizeModel(
      range: json['range'] ?? '',
      readHits: json['read_hits'] ?? 0,
      writeHits: json['write_hits'] ?? 0,
      percentage: (json['percentage'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class GlusterQuotasReportModel {
  final String volumeName;
  final bool quotaEnabled;
  final List<GlusterQuotaModel> quotas;

  GlusterQuotasReportModel({
    required this.volumeName,
    required this.quotaEnabled,
    required this.quotas,
  });

  factory GlusterQuotasReportModel.fromJson(Map<String, dynamic> json) {
    var list = <GlusterQuotaModel>[];
    if (json['quotas'] is List) {
      list = (json['quotas'] as List).map((q) => GlusterQuotaModel.fromJson(q)).toList();
    }
    return GlusterQuotasReportModel(
      volumeName: json['volume_name'] ?? '',
      quotaEnabled: json['quota_enabled'] ?? true,
      quotas: list,
    );
  }

  factory GlusterQuotasReportModel.empty(String name) {
    return GlusterQuotasReportModel(volumeName: name, quotaEnabled: false, quotas: []);
  }
}

class GlusterQuotaModel {
  final String id;
  final String volumeName;
  final String path;
  final String hardLimit;
  final String softLimit;
  final double usedMB;
  final double totalMB;
  final double percent;

  GlusterQuotaModel({
    required this.id,
    required this.volumeName,
    required this.path,
    required this.hardLimit,
    required this.softLimit,
    required this.usedMB,
    required this.totalMB,
    required this.percent,
  });

  factory GlusterQuotaModel.fromJson(Map<String, dynamic> json) {
    return GlusterQuotaModel(
      id: json['id'] ?? '',
      volumeName: json['volume_name'] ?? '',
      path: json['path'] ?? '/',
      hardLimit: json['hard_limit'] ?? 'Unlimited',
      softLimit: json['soft_limit'] ?? '80%',
      usedMB: (json['used_mb'] as num?)?.toDouble() ?? 0.0,
      totalMB: (json['total_mb'] as num?)?.toDouble() ?? 0.0,
      percent: (json['percent'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class GlusterSnapshotModel {
  final String id;
  final String name;
  final String volumeName;
  final String status;
  final String description;
  final String createdAt;

  GlusterSnapshotModel({
    required this.id,
    required this.name,
    required this.volumeName,
    required this.status,
    required this.description,
    required this.createdAt,
  });

  factory GlusterSnapshotModel.fromJson(Map<String, dynamic> json) {
    return GlusterSnapshotModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      volumeName: json['volume_name'] ?? '',
      status: json['status'] ?? 'Active',
      description: json['description'] ?? '',
      createdAt: json['created_at'] ?? '',
    );
  }
}





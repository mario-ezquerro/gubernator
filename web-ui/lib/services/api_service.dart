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

  static Future<String?> deployStack(String name, String compose) async {
    final response = await http.post(
      Uri.parse('/api/stack'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'compose': compose,
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

  /// Updates a node's availability status.
  static Future<bool> updateNodeAvailability(String id, String availability) async {
    final response = await http.post(
      Uri.parse('/api/node/$id/availability'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'availability': availability}),
    );
    return response.statusCode == 200;
  }

  /// Commands the node to leave the cluster.
  static Future<bool> leaveNode(String id) async {
    final response = await http.post(Uri.parse('/api/node/$id/leave'));
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
}


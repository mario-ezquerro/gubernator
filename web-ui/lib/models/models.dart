/// Data models matching the Go backend JSON responses.

class Node {
  final String id;
  final String ip;
  final String role;
  final String status;
  final Map<String, dynamic> labels;
  final String createdAt;
  final String updatedAt;

  Node({
    required this.id,
    required this.ip,
    required this.role,
    required this.status,
    this.labels = const {},
    this.createdAt = '',
    this.updatedAt = '',
  });

  factory Node.fromJson(Map<String, dynamic> json) {
    return Node(
      id: json['id'] ?? '',
      ip: json['ip'] ?? '',
      role: json['role'] ?? '',
      status: json['status'] ?? '',
      labels: json['labels'] ?? {},
      createdAt: json['created_at'] ?? '',
      updatedAt: json['updated_at'] ?? '',
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

class DashboardState {
  final List<Node> nodes;
  final List<StackModel> stacks;
  final List<Service> services;
  final List<Task> tasks;
  final bool monitorRunning;

  DashboardState({
    this.nodes = const [],
    this.stacks = const [],
    this.services = const [],
    this.tasks = const [],
    this.monitorRunning = false,
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
      monitorRunning: json['monitor_running'] ?? false,
    );
  }
}

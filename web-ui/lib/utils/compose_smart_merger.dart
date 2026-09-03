/// Result classification for Smart Merge operations.
enum MergeActionType {
  updated,
  added,
  alreadyExists,
  inserted,
}

/// Details returned by a smart merge operation.
class MergeResult {
  final String newYaml;
  final MergeActionType action;
  final String message;

  const MergeResult({
    required this.newYaml,
    required this.action,
    required this.message,
  });
}

/// Service line boundary helper.
class _ServiceBounds {
  final String name;
  final int startLine; // 0-indexed line where "  <service_name>:" is
  final int endLine;   // 0-indexed line where service ends (inclusive)
  final String indent; // e.g. "  "

  const _ServiceBounds({
    required this.name,
    required this.startLine,
    required this.endLine,
    required this.indent,
  });
}

/// Sub-block line boundary helper.
class _BlockBounds {
  final int keyLine;  // 0-indexed line where "<key>:" is
  final int endLine;  // 0-indexed line where block ends (inclusive)
  final int indentLength; // number of leading spaces

  const _BlockBounds({
    required this.keyLine,
    required this.endLine,
    required this.indentLength,
  });
}

/// Intelligent parser and manipulator for Docker Compose YAML in Gubernator Compose Studio.
/// Ensures singletons (resources, restart, healthcheck, role constraints, unique labels)
/// are updated in-place without duplicating blocks, while collections (volumes, ports, env)
/// are merged cleanly without creating redundant section headers or duplicate entries.
class ComposeSmartMerger {
  /// Resolves the target service bounds in the Compose document based on cursor offset.
  static _ServiceBounds? _findTargetService(List<String> lines, int cursorOffset) {
    int servicesIdx = -1;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].trim().startsWith('services:')) {
        servicesIdx = i;
        break;
      }
    }
    if (servicesIdx == -1) return null;

    // Calculate cursor line number
    int cursorLine = 0;
    int acc = 0;
    for (int i = 0; i < lines.length; i++) {
      acc += lines[i].length + 1; // +1 for newline
      if (cursorOffset < acc) {
        cursorLine = i;
        break;
      }
    }

    // Identify all services under "services:"
    final services = <_ServiceBounds>[];
    for (int i = servicesIdx + 1; i < lines.length; i++) {
      final line = lines[i];
      // Top-level key (0 indent) terminates services block
      if (line.isNotEmpty && !line.startsWith(' ') && !line.startsWith('\t') && !line.startsWith('#')) {
        break;
      }
      // Service name line (exactly 2 spaces indentation ending with :)
      final match = RegExp(r'^  ([a-zA-Z0-9_\-]+):').firstMatch(line);
      if (match != null) {
        final name = match.group(1)!;
        services.add(_ServiceBounds(
          name: name,
          startLine: i,
          endLine: lines.length - 1, // temporary, will fix below
          indent: '  ',
        ));
      }
    }

    if (services.isEmpty) return null;

    // Fix endLines for each service
    for (int i = 0; i < services.length; i++) {
      final nextStart = (i + 1 < services.length) ? services[i + 1].startLine - 1 : lines.length - 1;
      services[i] = _ServiceBounds(
        name: services[i].name,
        startLine: services[i].startLine,
        endLine: nextStart,
        indent: services[i].indent,
      );
    }

    // Try finding service enclosing cursor
    for (final s in services) {
      if (cursorLine >= s.startLine && cursorLine <= s.endLine) {
        return s;
      }
    }

    // Default to first service
    return services.first;
  }

  /// Finds a sub-block (e.g. "deploy:", "volumes:", "labels:") inside a line range.
  static _BlockBounds? _findSubBlock(List<String> lines, int start, int end, String key) {
    for (int i = start; i <= end; i++) {
      final line = lines[i];
      final trimmed = line.trim();
      if (trimmed == '$key:' || trimmed.startsWith('$key:')) {
        final indentLen = line.indexOf(key);
        // Find where this block ends (next line with indent <= indentLen that is not blank or comment)
        int blockEnd = i;
        for (int j = i + 1; j <= end; j++) {
          final l = lines[j];
          final t = l.trim();
          if (t.isEmpty || t.startsWith('#')) {
            blockEnd = j;
            continue;
          }
          final curIndent = l.indexOf(RegExp(r'\S'));
          if (curIndent > indentLen) {
            blockEnd = j;
          } else {
            break;
          }
        }
        return _BlockBounds(keyLine: i, endLine: blockEnd, indentLength: indentLen);
      }
    }
    return null;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 1. RESOURCES: Limits & Reservations (Singleton - Updates in-place)
  // ──────────────────────────────────────────────────────────────────────────

  static MergeResult mergeResources(
    String yaml,
    int cursorOffset, {
    required String cpuLimit,
    required String memLimit,
    required String cpuReserve,
    required String memReserve,
  }) {
    var lines = yaml.split('\n');
    final srv = _findTargetService(lines, cursorOffset);

    if (srv == null) {
      // Fallback: append snippet
      final snippet = '''
    deploy:
      resources:
        limits:
          cpus: "$cpuLimit"
          memory: $memLimit
        reservations:
          cpus: "$cpuReserve"
          memory: $memReserve
''';
      return MergeResult(
        newYaml: yaml + (yaml.endsWith('\n') ? '' : '\n') + snippet,
        action: MergeActionType.inserted,
        message: 'Inserted resource limits ($cpuLimit CPU / $memLimit)',
      );
    }

    final deployBlock = _findSubBlock(lines, srv.startLine, srv.endLine, 'deploy');

    if (deployBlock != null) {
      final resBlock = _findSubBlock(lines, deployBlock.keyLine, deployBlock.endLine, 'resources');
      if (resBlock != null) {
        // Resources block already exists! Check if exact same configuration
        final currentContent = lines.sublist(resBlock.keyLine, resBlock.endLine + 1).join('\n');
        if (currentContent.contains('cpus: "$cpuLimit"') &&
            currentContent.contains('memory: $memLimit') &&
            currentContent.contains('cpus: "$cpuReserve"') &&
            currentContent.contains('memory: $memReserve')) {
          return MergeResult(
            newYaml: yaml,
            action: MergeActionType.alreadyExists,
            message: 'Resource limits are already set to $cpuLimit CPU / $memLimit',
          );
        }

        // Resources block already exists! Replace it in-place
        final resIndent = ' ' * resBlock.indentLength;
        final subIndent = ' ' * (resBlock.indentLength + 2);
        final itemIndent = ' ' * (resBlock.indentLength + 4);

        final newLines = <String>[
          '${resIndent}resources:',
          '${subIndent}limits:',
          '${itemIndent}cpus: "$cpuLimit"',
          '${itemIndent}memory: $memLimit',
          '${subIndent}reservations:',
          '${itemIndent}cpus: "$cpuReserve"',
          '${itemIndent}memory: $memReserve',
        ];

        lines.replaceRange(resBlock.keyLine, resBlock.endLine + 1, newLines);
        return MergeResult(
          newYaml: lines.join('\n'),
          action: MergeActionType.updated,
          message: 'Updated resource limits in-place ($cpuLimit CPU / $memLimit)',
        );
      } else {
        // deploy: exists, but no resources: -> Insert inside deploy:
        final resIndent = ' ' * (deployBlock.indentLength + 2);
        final subIndent = ' ' * (deployBlock.indentLength + 4);
        final itemIndent = ' ' * (deployBlock.indentLength + 6);

        final newLines = <String>[
          '${resIndent}resources:',
          '${subIndent}limits:',
          '${itemIndent}cpus: "$cpuLimit"',
          '${itemIndent}memory: $memLimit',
          '${subIndent}reservations:',
          '${itemIndent}cpus: "$cpuReserve"',
          '${itemIndent}memory: $memReserve',
        ];

        lines.insertAll(deployBlock.keyLine + 1, newLines);
        return MergeResult(
          newYaml: lines.join('\n'),
          action: MergeActionType.added,
          message: 'Added resource limits to deploy ($cpuLimit CPU / $memLimit)',
        );
      }
    } else {
      // Neither deploy nor resources exist -> Insert deploy + resources in service
      final newLines = <String>[
        '    deploy:',
        '      resources:',
        '        limits:',
        '          cpus: "$cpuLimit"',
        '          memory: $memLimit',
        '        reservations:',
        '          cpus: "$cpuReserve"',
        '          memory: $memReserve',
      ];
      lines.insertAll(srv.startLine + 1, newLines);
      return MergeResult(
        newYaml: lines.join('\n'),
        action: MergeActionType.inserted,
        message: 'Configured resource limits ($cpuLimit CPU / $memLimit)',
      );
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 2. RESTART POLICY: (Singleton - Updates in-place)
  // ──────────────────────────────────────────────────────────────────────────

  static MergeResult mergeRestartPolicy(String yaml, int cursorOffset, String policy) {
    var lines = yaml.split('\n');
    final srv = _findTargetService(lines, cursorOffset);

    if (srv == null) {
      final snippet = '    restart: $policy\n';
      return MergeResult(
        newYaml: yaml + (yaml.endsWith('\n') ? '' : '\n') + snippet,
        action: MergeActionType.inserted,
        message: 'Set restart policy to $policy',
      );
    }

    for (int i = srv.startLine; i <= srv.endLine; i++) {
      final line = lines[i];
      if (line.trim().startsWith('restart:')) {
        final currentPolicy = line.trim().replaceFirst('restart:', '').trim();
        if (currentPolicy == policy) {
          return MergeResult(
            newYaml: yaml,
            action: MergeActionType.alreadyExists,
            message: 'Restart policy is already set to $policy',
          );
        }
        final indent = line.substring(0, line.indexOf('restart:'));
        lines[i] = '${indent}restart: $policy';
        return MergeResult(
          newYaml: lines.join('\n'),
          action: MergeActionType.updated,
          message: 'Updated restart policy in-place to $policy',
        );
      }
    }

    // Not found -> insert after service definition line
    lines.insert(srv.startLine + 1, '    restart: $policy');
    return MergeResult(
      newYaml: lines.join('\n'),
      action: MergeActionType.inserted,
      message: 'Added restart policy: $policy',
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 3. HEALTHCHECK: (Singleton - Updates in-place)
  // ──────────────────────────────────────────────────────────────────────────

  static MergeResult mergeHealthcheck(
    String yaml,
    int cursorOffset, {
    required String testCmd,
    String interval = '10s',
    String timeout = '5s',
    int retries = 3,
  }) {
    var lines = yaml.split('\n');
    final srv = _findTargetService(lines, cursorOffset);

    final healthcheckLines = <String>[
      '    healthcheck:',
      '      test: ["CMD", "curl", "-f", "$testCmd"]',
      '      interval: $interval',
      '      timeout: $timeout',
      '      retries: $retries',
    ];

    if (srv == null) {
      final sep = yaml.endsWith('\n') ? '' : '\n';
      return MergeResult(
        newYaml: '$yaml$sep${healthcheckLines.join('\n')}\n',
        action: MergeActionType.inserted,
        message: 'Inserted container healthcheck probe',
      );
    }

    final hcBlock = _findSubBlock(lines, srv.startLine, srv.endLine, 'healthcheck');
    if (hcBlock != null) {
      final currentContent = lines.sublist(hcBlock.keyLine, hcBlock.endLine + 1).join('\n');
      if (currentContent.contains(testCmd)) {
        return MergeResult(
          newYaml: yaml,
          action: MergeActionType.alreadyExists,
          message: 'Healthcheck probe is already configured',
        );
      }
      lines.replaceRange(hcBlock.keyLine, hcBlock.endLine + 1, healthcheckLines);
      return MergeResult(
        newYaml: lines.join('\n'),
        action: MergeActionType.updated,
        message: 'Updated container healthcheck probe in-place',
      );
    } else {
      lines.insertAll(srv.startLine + 1, healthcheckLines);
      return MergeResult(
        newYaml: lines.join('\n'),
        action: MergeActionType.inserted,
        message: 'Added container healthcheck probe',
      );
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 4. PLACEMENT CONSTRAINTS: Hardware & Node Affinity (Smart Merge)
  // ──────────────────────────────────────────────────────────────────────────

  static MergeResult mergePlacementConstraint(
    String yaml,
    int cursorOffset, {
    required String constraint,
    String? replacePrefix, // e.g. "node.role ==" or "node.hostname =="
  }) {
    var lines = yaml.split('\n');
    final srv = _findTargetService(lines, cursorOffset);

    if (srv == null) {
      final snippet = '''
    deploy:
      placement:
        constraints:
          - "$constraint"
''';
      return MergeResult(
        newYaml: yaml + (yaml.endsWith('\n') ? '' : '\n') + snippet,
        action: MergeActionType.inserted,
        message: 'Added placement constraint: $constraint',
      );
    }

    final deployBlock = _findSubBlock(lines, srv.startLine, srv.endLine, 'deploy');

    if (deployBlock != null) {
      final placementBlock = _findSubBlock(lines, deployBlock.keyLine, deployBlock.endLine, 'placement');
      if (placementBlock != null) {
        final constraintsBlock = _findSubBlock(lines, placementBlock.keyLine, placementBlock.endLine, 'constraints');
        if (constraintsBlock != null) {
          // Check existing constraints
          for (int i = constraintsBlock.keyLine + 1; i <= constraintsBlock.endLine; i++) {
            final line = lines[i];
            final clean = line.replaceAll('"', '').replaceAll("'", "").trim();
            // Check exact duplicate
            if (clean == '- $constraint' || clean == constraint) {
              return MergeResult(
                newYaml: yaml,
                action: MergeActionType.alreadyExists,
                message: 'Constraint "$constraint" is already active',
              );
            }
            // Check in-place replace (e.g. changing worker to manager, or changing pinned node)
            if (replacePrefix != null && clean.contains(replacePrefix)) {
              final indent = line.substring(0, line.indexOf('-'));
              lines[i] = '$indent- "$constraint"';
              return MergeResult(
                newYaml: lines.join('\n'),
                action: MergeActionType.updated,
                message: 'Updated placement constraint in-place: $constraint',
              );
            }
          }

          // Append to existing constraints:
          final lastLine = lines[constraintsBlock.endLine];
          final indent = lastLine.contains('-') ? lastLine.substring(0, lastLine.indexOf('-')) : '          ';
          lines.insert(constraintsBlock.endLine + 1, '$indent- "$constraint"');
          return MergeResult(
            newYaml: lines.join('\n'),
            action: MergeActionType.added,
            message: 'Added constraint to placement: $constraint',
          );
        } else {
          // placement: exists but no constraints: -> insert constraints
          final cIndent = ' ' * (placementBlock.indentLength + 2);
          final itemIndent = ' ' * (placementBlock.indentLength + 4);
          final newLines = [
            '$cIndent constraints:',
            '$itemIndent- "$constraint"',
          ];
          lines.insertAll(placementBlock.keyLine + 1, newLines);
          return MergeResult(
            newYaml: lines.join('\n'),
            action: MergeActionType.added,
            message: 'Added placement constraint: $constraint',
          );
        }
      } else {
        // deploy: exists but no placement: -> insert placement + constraints
        final pIndent = ' ' * (deployBlock.indentLength + 2);
        final cIndent = ' ' * (deployBlock.indentLength + 4);
        final itemIndent = ' ' * (deployBlock.indentLength + 6);
        final newLines = [
          '$pIndent placement:',
          '$cIndent constraints:',
          '$itemIndent- "$constraint"',
        ];
        lines.insertAll(deployBlock.keyLine + 1, newLines);
        return MergeResult(
          newYaml: lines.join('\n'),
          action: MergeActionType.added,
          message: 'Configured placement constraint: $constraint',
        );
      }
    } else {
      // Neither deploy nor placement exists
      final newLines = [
        '    deploy:',
        '      placement:',
        '        constraints:',
        '          - "$constraint"',
      ];
      lines.insertAll(srv.startLine + 1, newLines);
      return MergeResult(
        newYaml: lines.join('\n'),
        action: MergeActionType.inserted,
        message: 'Configured placement constraint: $constraint',
      );
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 5. LABELS: Caddy, Sloth SLO, Security Gatekeeper (Smart Merge / Updates)
  // ──────────────────────────────────────────────────────────────────────────

  static MergeResult mergeLabels(
    String yaml,
    int cursorOffset,
    List<MapEntry<String, String>> labels, {
    String? categoryTitle,
  }) {
    var lines = yaml.split('\n');
    final srv = _findTargetService(lines, cursorOffset);

    if (srv == null) {
      final labelLines = ['    labels:'];
      for (final e in labels) {
        labelLines.add('      - "${e.key}=${e.value}"');
      }
      final sep = yaml.endsWith('\n') ? '' : '\n';
      return MergeResult(
        newYaml: '$yaml$sep${labelLines.join('\n')}\n',
        action: MergeActionType.inserted,
        message: 'Inserted ${categoryTitle ?? 'labels'}',
      );
    }

    final labelsBlock = _findSubBlock(lines, srv.startLine, srv.endLine, 'labels');

    if (labelsBlock != null) {
      int updatedCount = 0;
      int addedCount = 0;

      for (final entry in labels) {
        final key = entry.key;
        final val = entry.value;
        bool found = false;

        for (int i = labelsBlock.keyLine + 1; i <= labelsBlock.endLine; i++) {
          final line = lines[i];
          final clean = line.replaceAll('"', '').replaceAll("'", "").trim();
          if (clean.contains('$key=')) {
            found = true;
            final currentVal = clean.split('$key=').last;
            if (currentVal != val) {
              final indent = line.contains('-') ? line.substring(0, line.indexOf('-')) : '      ';
              lines[i] = '$indent- "$key=$val"';
              updatedCount++;
            }
            break;
          }
        }

        if (!found) {
          // Append to end of labels block
          final lastLine = lines[labelsBlock.endLine];
          final indent = lastLine.contains('-') ? lastLine.substring(0, lastLine.indexOf('-')) : '      ';
          lines.insert(labelsBlock.endLine + 1, '$indent- "$key=$val"');
          addedCount++;
        }
      }

      if (updatedCount > 0) {
        return MergeResult(
          newYaml: lines.join('\n'),
          action: MergeActionType.updated,
          message: 'Updated ${categoryTitle ?? 'labels'} in-place',
        );
      } else if (addedCount > 0) {
        return MergeResult(
          newYaml: lines.join('\n'),
          action: MergeActionType.added,
          message: 'Added ${categoryTitle ?? 'labels'} to service',
        );
      } else {
        return MergeResult(
          newYaml: yaml,
          action: MergeActionType.alreadyExists,
          message: '${categoryTitle ?? 'Labels'} already configured in compose',
        );
      }
    } else {
      // Create new labels: block
      final newLines = ['    labels:'];
      for (final e in labels) {
        newLines.add('      - "${e.key}=${e.value}"');
      }
      lines.insertAll(srv.startLine + 1, newLines);
      return MergeResult(
        newYaml: lines.join('\n'),
        action: MergeActionType.inserted,
        message: 'Configured ${categoryTitle ?? 'labels'}',
      );
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 6. VOLUMES: Multi-mount Collection (Appends without duplicate sections)
  // ──────────────────────────────────────────────────────────────────────────

  static MergeResult mergeVolumeMount(String yaml, int cursorOffset, String mount) {
    var lines = yaml.split('\n');
    final srv = _findTargetService(lines, cursorOffset);

    if (srv == null) {
      final snippet = '    volumes:\n      - $mount\n';
      return MergeResult(
        newYaml: yaml + (yaml.endsWith('\n') ? '' : '\n') + snippet,
        action: MergeActionType.inserted,
        message: 'Added volume mount: $mount',
      );
    }

    final volBlock = _findSubBlock(lines, srv.startLine, srv.endLine, 'volumes');

    if (volBlock != null) {
      // Check if this mount already exists
      for (int i = volBlock.keyLine + 1; i <= volBlock.endLine; i++) {
        final clean = lines[i].replaceAll('"', '').replaceAll("'", "").trim();
        if (clean == '- $mount' || clean == mount) {
          return MergeResult(
            newYaml: yaml,
            action: MergeActionType.alreadyExists,
            message: 'Volume "$mount" already configured in compose',
          );
        }
      }

      // Append mount to existing volumes: list
      final lastLine = lines[volBlock.endLine];
      final indent = lastLine.contains('-') ? lastLine.substring(0, lastLine.indexOf('-')) : '      ';
      lines.insert(volBlock.endLine + 1, '$indent- $mount');
      return MergeResult(
        newYaml: lines.join('\n'),
        action: MergeActionType.added,
        message: 'Added volume mount to existing volumes ($mount)',
      );
    } else {
      // Insert new volumes: block
      final newLines = [
        '    volumes:',
        '      - $mount',
      ];
      lines.insertAll(srv.startLine + 1, newLines);
      return MergeResult(
        newYaml: lines.join('\n'),
        action: MergeActionType.inserted,
        message: 'Configured volume mount ($mount)',
      );
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 7. PORTS: Multi-port Collection (Appends without duplicate sections)
  // ──────────────────────────────────────────────────────────────────────────

  static MergeResult mergePorts(String yaml, int cursorOffset, List<String> ports) {
    var lines = yaml.split('\n');
    final srv = _findTargetService(lines, cursorOffset);

    if (srv == null) {
      final portLines = ['    ports:'];
      for (final p in ports) {
        portLines.add('      - "$p"');
      }
      final sep = yaml.endsWith('\n') ? '' : '\n';
      return MergeResult(
        newYaml: '$yaml$sep${portLines.join('\n')}\n',
        action: MergeActionType.inserted,
        message: 'Added port mappings: ${ports.join(', ')}',
      );
    }

    final portsBlock = _findSubBlock(lines, srv.startLine, srv.endLine, 'ports');

    if (portsBlock != null) {
      final toAdd = <String>[];
      for (final p in ports) {
        bool exists = false;
        for (int i = portsBlock.keyLine + 1; i <= portsBlock.endLine; i++) {
          final clean = lines[i].replaceAll('"', '').replaceAll("'", "").trim();
          if (clean == '- $p' || clean == p || clean == '- "$p"') {
            exists = true;
            break;
          }
        }
        if (!exists) {
          toAdd.add(p);
        }
      }

      if (toAdd.isEmpty) {
        return MergeResult(
          newYaml: yaml,
          action: MergeActionType.alreadyExists,
          message: 'Ports ${ports.join(', ')} already mapped in compose',
        );
      }

      final lastLine = lines[portsBlock.endLine];
      final indent = lastLine.contains('-') ? lastLine.substring(0, lastLine.indexOf('-')) : '      ';
      final newLines = toAdd.map((p) => '$indent- "$p"').toList();
      lines.insertAll(portsBlock.endLine + 1, newLines);
      return MergeResult(
        newYaml: lines.join('\n'),
        action: MergeActionType.added,
        message: 'Added ports to existing list: ${toAdd.join(', ')}',
      );
    } else {
      // Insert new ports: block
      final newLines = ['    ports:'];
      for (final p in ports) {
        newLines.add('      - "$p"');
      }
      lines.insertAll(srv.startLine + 1, newLines);
      return MergeResult(
        newYaml: lines.join('\n'),
        action: MergeActionType.inserted,
        message: 'Configured ports: ${ports.join(', ')}',
      );
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 8. ENVIRONMENT VARIABLES: (Smart Key-Value Merge)
  // ──────────────────────────────────────────────────────────────────────────

  static MergeResult mergeEnvironment(String yaml, int cursorOffset, List<MapEntry<String, String>> envVars) {
    var lines = yaml.split('\n');
    final srv = _findTargetService(lines, cursorOffset);

    if (srv == null) {
      final envLines = ['    environment:'];
      for (final e in envVars) {
        envLines.add('      - ${e.key}=${e.value}');
      }
      final sep = yaml.endsWith('\n') ? '' : '\n';
      return MergeResult(
        newYaml: '$yaml$sep${envLines.join('\n')}\n',
        action: MergeActionType.inserted,
        message: 'Configured environment variables',
      );
    }

    final envBlock = _findSubBlock(lines, srv.startLine, srv.endLine, 'environment');

    if (envBlock != null) {
      int updated = 0;

      for (final entry in envVars) {
        final key = entry.key;
        final val = entry.value;
        bool found = false;

        for (int i = envBlock.keyLine + 1; i <= envBlock.endLine; i++) {
          final clean = lines[i].trim();
          if (clean.startsWith('- $key=') || clean.startsWith('$key=')) {
            found = true;
            final indent = lines[i].contains('-') ? lines[i].substring(0, lines[i].indexOf('-')) : '      ';
            lines[i] = '$indent- $key=$val';
            updated++;
            break;
          }
        }

        if (!found) {
          final lastLine = lines[envBlock.endLine];
          final indent = lastLine.contains('-') ? lastLine.substring(0, lastLine.indexOf('-')) : '      ';
          lines.insert(envBlock.endLine + 1, '$indent- $key=$val');
        }
      }

      return MergeResult(
        newYaml: lines.join('\n'),
        action: updated > 0 ? MergeActionType.updated : MergeActionType.added,
        message: updated > 0 ? 'Updated environment variables in-place' : 'Added environment variables to service',
      );
    } else {
      final newLines = ['    environment:'];
      for (final e in envVars) {
        newLines.add('      - ${e.key}=${e.value}');
      }
      lines.insertAll(srv.startLine + 1, newLines);
      return MergeResult(
        newYaml: lines.join('\n'),
        action: MergeActionType.inserted,
        message: 'Configured environment variables',
      );
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 9. AUTOMATIC SMART MERGE DETECTOR (Fallback for Generic Snippets)
  // ──────────────────────────────────────────────────────────────────────────

  static MergeResult? trySmartMerge(String yaml, int cursorOffset, String snippet) {
    final clean = snippet.trim();

    // 1. Resources
    if (snippet.contains('resources:') && (snippet.contains('limits:') || snippet.contains('cpus:'))) {
      String? cpuLim;
      String? memLim;
      String? cpuRes;
      String? memRes;

      final sLines = snippet.split('\n');
      bool inRes = false;

      for (final l in sLines) {
        final t = l.trim();
        if (t == 'reservations:') {
          inRes = true;
        } else if (t == 'limits:') {
          inRes = false;
        } else if (t.startsWith('cpus:')) {
          final val = t.replaceFirst('cpus:', '').replaceAll('"', '').trim();
          if (inRes) {
            cpuRes = val;
          } else {
            cpuLim = val;
          }
        } else if (t.startsWith('memory:')) {
          final val = t.replaceFirst('memory:', '').replaceAll('"', '').trim();
          if (inRes) {
            memRes = val;
          } else {
            memLim = val;
          }
        }
      }

      return mergeResources(
        yaml,
        cursorOffset,
        cpuLimit: cpuLim ?? '1.0',
        memLimit: memLim ?? '512M',
        cpuReserve: cpuRes ?? '0.25',
        memReserve: memRes ?? '128M',
      );
    }

    // 2. Restart Policy
    if (clean.startsWith('restart:')) {
      final policy = clean.replaceFirst('restart:', '').trim();
      return mergeRestartPolicy(yaml, cursorOffset, policy);
    }

    // 3. Healthcheck
    if (snippet.contains('healthcheck:')) {
      String testCmd = 'http://localhost:8080/health';
      for (final l in snippet.split('\n')) {
        final t = l.trim();
        if (t.contains('curl') && t.contains('http')) {
          final startIdx = t.indexOf('http');
          final endIdx = t.indexOf('"', startIdx);
          if (startIdx != -1 && endIdx != -1) {
            testCmd = t.substring(startIdx, endIdx);
          }
        }
      }
      return mergeHealthcheck(yaml, cursorOffset, testCmd: testCmd);
    }

    // 4. Placement Constraints
    if (snippet.contains('placement:') && snippet.contains('constraints:')) {
      for (final l in snippet.split('\n')) {
        final t = l.trim();
        if (t.startsWith('-')) {
          final c = t.substring(1).replaceAll('"', '').replaceAll("'", "").trim();
          String? prefix;
          if (c.contains('==')) {
            prefix = '${c.split('==').first.trim()} ==';
          }
          return mergePlacementConstraint(yaml, cursorOffset, constraint: c, replacePrefix: prefix);
        }
      }
    }

    // 5. Ports
    if (clean.startsWith('ports:')) {
      final ports = <String>[];
      for (final l in snippet.split('\n')) {
        final t = l.trim();
        if (t.startsWith('-')) {
          ports.add(t.substring(1).replaceAll('"', '').replaceAll("'", "").trim());
        }
      }
      if (ports.isNotEmpty) {
        return mergePorts(yaml, cursorOffset, ports);
      }
    }

    // 6. Volumes
    if (clean.startsWith('volumes:') || clean.startsWith('- /var/contenedores/') || clean.startsWith('- ./')) {
      String? mount;
      for (final l in snippet.split('\n')) {
        final t = l.trim();
        if (t.startsWith('-')) {
          mount = t.substring(1).trim();
          break;
        }
      }
      if (mount != null && mount.isNotEmpty) {
        return mergeVolumeMount(yaml, cursorOffset, mount);
      }
    }

    // 7. Environment
    if (clean.startsWith('environment:')) {
      final envVars = <MapEntry<String, String>>[];
      for (final l in snippet.split('\n')) {
        final t = l.trim();
        if (t.startsWith('-') && t.contains('=')) {
          final line = t.substring(1).trim();
          final parts = line.split('=');
          envVars.add(MapEntry(parts.first.trim(), parts.sublist(1).join('=').trim()));
        }
      }
      if (envVars.isNotEmpty) {
        return mergeEnvironment(yaml, cursorOffset, envVars);
      }
    }

    // 8. Labels
    if (clean.startsWith('labels:') || clean.startsWith('- "ingress.host') || clean.startsWith('- "gbnt.')) {
      final labels = <MapEntry<String, String>>[];
      for (final l in snippet.split('\n')) {
        final t = l.trim();
        if (t.startsWith('-') && t.contains('=')) {
          final line = t.substring(1).replaceAll('"', '').replaceAll("'", "").trim();
          final parts = line.split('=');
          labels.add(MapEntry(parts.first.trim(), parts.sublist(1).join('=').trim()));
        }
      }
      if (labels.isNotEmpty) {
        return mergeLabels(yaml, cursorOffset, labels);
      }
    }

    return null;
  }
}

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
  /// Finds all service definitions under "services:" in the Compose document.
  static List<_ServiceBounds> _findAllServices(List<String> lines) {
    int servicesIdx = -1;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].trim().startsWith('services:')) {
        servicesIdx = i;
        break;
      }
    }
    if (servicesIdx == -1) return [];

    final services = <_ServiceBounds>[];
    for (int i = servicesIdx + 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.isNotEmpty && !line.startsWith(' ') && !line.startsWith('\t') && !line.startsWith('#')) {
        break;
      }
      final match = RegExp(r'^  ([a-zA-Z0-9_\-]+):').firstMatch(line);
      if (match != null) {
        final name = match.group(1)!;
        services.add(_ServiceBounds(
          name: name,
          startLine: i,
          endLine: lines.length - 1,
          indent: '  ',
        ));
      }
    }

    for (int i = 0; i < services.length; i++) {
      final nextStart = (i + 1 < services.length) ? services[i + 1].startLine - 1 : lines.length - 1;
      services[i] = _ServiceBounds(
        name: services[i].name,
        startLine: services[i].startLine,
        endLine: nextStart,
        indent: services[i].indent,
      );
    }
    return services;
  }

  /// Resolves the target service bounds in the Compose document based on cursor offset.
  static _ServiceBounds? _findTargetService(List<String> lines, int cursorOffset) {
    final services = _findAllServices(lines);
    if (services.isEmpty) return null;

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
  // 5. LABELS: Unified Labels-First Engine (Smart Merge, Remove, Toggle)
  // ──────────────────────────────────────────────────────────────────────────

  /// Checks if a YAML line defines the given label key in any format:
  /// "- key=val", "- \"key=val\"", "key: val", "- key: val", etc.
  static bool _lineMatchesLabelKey(String line, String key) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) return false;
    final clean = trimmed
        .replaceAll('"', '')
        .replaceAll("'", "")
        .replaceAll(RegExp(r'^-\s*'), '')
        .trim();

    if (clean.startsWith('$key=') || clean.startsWith('$key:') || clean == key) {
      return true;
    }
    return false;
  }

  /// Extracts the value of a label line given its key.
  static String _extractLabelValue(String line, String key) {
    final trimmed = line.trim();
    final clean = trimmed
        .replaceAll('"', '')
        .replaceAll("'", "")
        .replaceAll(RegExp(r'^-\s*'), '')
        .trim();

    if (clean.startsWith('$key=')) {
      return clean.substring(key.length + 1).trim();
    }
    if (clean.startsWith('$key:')) {
      return clean.substring(key.length + 1).trim();
    }
    return '';
  }

  /// Checks whether the target service at cursor offset has the specified label key.
  /// If [expectedValue] is provided, also verifies that the value matches.
  static bool hasLabel(String yaml, int cursorOffset, String key, [String? expectedValue]) {
    final lines = yaml.split('\n');
    final srv = _findTargetService(lines, cursorOffset);
    if (srv == null) return false;

    final labelsBlock = _findSubBlock(lines, srv.startLine, srv.endLine, 'labels');
    if (labelsBlock == null) return false;

    for (int i = labelsBlock.keyLine + 1; i <= labelsBlock.endLine; i++) {
      final line = lines[i];
      if (_lineMatchesLabelKey(line, key)) {
        if (expectedValue == null) return true;
        final val = _extractLabelValue(line, key);
        if (val == expectedValue || val == '"$expectedValue"' || val == "'$expectedValue'") {
          return true;
        }
      }
    }
    return false;
  }

  /// Checks whether all entries in the list are active in the target service.
  static bool hasAllLabels(String yaml, int cursorOffset, List<MapEntry<String, String>> labels) {
    if (labels.isEmpty) return false;
    for (final e in labels) {
      if (!hasLabel(yaml, cursorOffset, e.key, e.value)) {
        return false;
      }
    }
    return true;
  }

  /// Removes the specified label keys from the target service.
  /// If the labels block becomes completely empty, removes the "labels:" header too.
  static MergeResult removeLabels(
    String yaml,
    int cursorOffset,
    List<String> keysToRemove, {
    String? categoryTitle,
  }) {
    var lines = yaml.split('\n');
    final srv = _findTargetService(lines, cursorOffset);
    if (srv == null) {
      return MergeResult(
        newYaml: yaml,
        action: MergeActionType.alreadyExists,
        message: 'No target service found to remove labels',
      );
    }

    final labelsBlock = _findSubBlock(lines, srv.startLine, srv.endLine, 'labels');
    if (labelsBlock == null) {
      return MergeResult(
        newYaml: yaml,
        action: MergeActionType.alreadyExists,
        message: 'No labels block in service',
      );
    }

    final toRemoveIdxs = <int>{};
    for (int i = labelsBlock.keyLine + 1; i <= labelsBlock.endLine; i++) {
      final line = lines[i];
      for (final k in keysToRemove) {
        if (_lineMatchesLabelKey(line, k)) {
          toRemoveIdxs.add(i);
          break;
        }
      }
    }

    if (toRemoveIdxs.isEmpty) {
      return MergeResult(
        newYaml: yaml,
        action: MergeActionType.alreadyExists,
        message: '${categoryTitle ?? 'Labels'} were not present in service',
      );
    }

    // Filter out lines in descending order
    final newLines = <String>[];
    for (int i = 0; i < lines.length; i++) {
      if (!toRemoveIdxs.contains(i)) {
        newLines.add(lines[i]);
      }
    }

    // Check if the labels block is now empty (only contains whitespace/comments before next block)
    final newSrv = _findTargetService(newLines, cursorOffset);
    if (newSrv != null) {
      final newLabelsBlock = _findSubBlock(newLines, newSrv.startLine, newSrv.endLine, 'labels');
      if (newLabelsBlock != null) {
        bool hasItems = false;
        for (int i = newLabelsBlock.keyLine + 1; i <= newLabelsBlock.endLine; i++) {
          final t = newLines[i].trim();
          if (t.isNotEmpty && !t.startsWith('#')) {
            hasItems = true;
            break;
          }
        }
        if (!hasItems) {
          // Remove empty labels block
          newLines.removeRange(newLabelsBlock.keyLine, newLabelsBlock.endLine + 1);
        }
      }
    }

    return MergeResult(
      newYaml: newLines.join('\n'),
      action: MergeActionType.updated,
      message: 'Removed ${categoryTitle ?? 'labels'} from service',
    );
  }

  /// Toggles the specified labels on or off in the target service.
  /// If all labels are already active, removes them.
  /// If any label is missing or different, merges them.
  static MergeResult toggleLabels(
    String yaml,
    int cursorOffset,
    List<MapEntry<String, String>> labels, {
    String? categoryTitle,
  }) {
    if (hasAllLabels(yaml, cursorOffset, labels)) {
      return removeLabels(
        yaml,
        cursorOffset,
        labels.map((e) => e.key).toList(),
        categoryTitle: categoryTitle,
      );
    } else {
      return mergeLabels(
        yaml,
        cursorOffset,
        labels,
        categoryTitle: categoryTitle,
      );
    }
  }

  /// Merges labels into the target service without duplicating keys.
  /// In-place updates existing keys or appends new keys with correct indentation.
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
          if (_lineMatchesLabelKey(line, key)) {
            found = true;
            final currentVal = _extractLabelValue(line, key);
            if (currentVal != val) {
              final indent = line.contains('-') ? line.substring(0, line.indexOf('-')) : '      ';
              lines[i] = '$indent- "$key=$val"';
              updatedCount++;
            }
            break;
          }
        }

        if (!found) {
          // Append to end of labels block with consistent 6-space indent
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
  // 9. DNS RESOLVERS & SEARCH DOMAINS: (CoreDNS Smart Merge)
  // ──────────────────────────────────────────────────────────────────────────

  static MergeResult mergeDNS(
    String yaml,
    int cursorOffset, {
    required List<String> dnsServers,
    List<String>? searchDomains,
    bool allServices = false,
  }) {
    var lines = yaml.split('\n');
    final allSrvs = _findAllServices(lines);
    if (allSrvs.isEmpty) {
      final dnsLines = ['services:', '  app:', '    dns:'];
      for (final d in dnsServers) {
        dnsLines.add('      - "$d"');
      }
      if (searchDomains != null && searchDomains.isNotEmpty) {
        dnsLines.add('    dns_search:');
        for (final s in searchDomains) {
          dnsLines.add('      - "$s"');
        }
      }
      final sep = yaml.endsWith('\n') ? '' : '\n';
      return MergeResult(
        newYaml: '$yaml$sep${dnsLines.join('\n')}\n',
        action: MergeActionType.inserted,
        message: 'Injected CoreDNS configuration',
      );
    }

    final targetServices = allServices
        ? allSrvs.reversed.toList()
        : [_findTargetService(lines, cursorOffset)!];

    bool anyModified = false;
    final messages = <String>[];

    for (final srv in targetServices) {
      // 1. Process dns: block
      final dnsBlock = _findSubBlock(lines, srv.startLine, srv.endLine, 'dns');
      if (dnsBlock != null) {
        final toAdd = <String>[];
        for (final d in dnsServers) {
          bool exists = false;
          for (int i = dnsBlock.keyLine + 1; i <= dnsBlock.endLine; i++) {
            final clean = lines[i].replaceAll('"', '').replaceAll("'", "").trim();
            if (clean == '- $d' || clean == d || clean == '- "$d"') {
              exists = true;
              break;
            }
          }
          if (!exists) toAdd.add(d);
        }
        if (toAdd.isNotEmpty) {
          anyModified = true;
          final lastLine = lines[dnsBlock.endLine];
          final indent = lastLine.contains('-') ? lastLine.substring(0, lastLine.indexOf('-')) : '      ';
          final newLines = toAdd.map((d) => '$indent- "$d"').toList();
          lines.insertAll(dnsBlock.endLine + 1, newLines);
        }
      } else {
        anyModified = true;
        final newLines = ['    dns:'];
        for (final d in dnsServers) {
          newLines.add('      - "$d"');
        }
        lines.insertAll(srv.startLine + 1, newLines);
      }

      // Re-find service bounds since lines changed
      final updatedSrv = _findAllServices(lines).firstWhere(
        (s) => s.name == srv.name,
        orElse: () => srv,
      );

      // 2. Process dns_search: block if requested
      if (searchDomains != null && searchDomains.isNotEmpty) {
        final searchBlock = _findSubBlock(lines, updatedSrv.startLine, updatedSrv.endLine, 'dns_search');
        if (searchBlock != null) {
          final toAdd = <String>[];
          for (final dom in searchDomains) {
            bool exists = false;
            for (int i = searchBlock.keyLine + 1; i <= searchBlock.endLine; i++) {
              final clean = lines[i].replaceAll('"', '').replaceAll("'", "").trim();
              if (clean == '- $dom' || clean == dom || clean == '- "$dom"') {
                exists = true;
                break;
              }
            }
            if (!exists) toAdd.add(dom);
          }
          if (toAdd.isNotEmpty) {
            anyModified = true;
            final lastLine = lines[searchBlock.endLine];
            final indent = lastLine.contains('-') ? lastLine.substring(0, lastLine.indexOf('-')) : '      ';
            final newLines = toAdd.map((dom) => '$indent- "$dom"').toList();
            lines.insertAll(searchBlock.endLine + 1, newLines);
          }
        } else {
          final currentDns = _findSubBlock(lines, updatedSrv.startLine, updatedSrv.endLine, 'dns');
          int insertAt = (currentDns != null) ? currentDns.endLine + 1 : updatedSrv.startLine + 1;
          anyModified = true;
          final newLines = ['    dns_search:'];
          for (final dom in searchDomains) {
            newLines.add('      - "$dom"');
          }
          lines.insertAll(insertAt, newLines);
        }
      }

      messages.add('${srv.name} (DNS: ${dnsServers.join(', ')})');
    }

    if (!anyModified) {
      return MergeResult(
        newYaml: yaml,
        action: MergeActionType.alreadyExists,
        message: 'CoreDNS configuration already present in compose',
      );
    }

    return MergeResult(
      newYaml: lines.join('\n'),
      action: MergeActionType.added,
      message: allServices
          ? 'Injected CoreDNS into all services: ${messages.join('; ')}'
          : 'Injected CoreDNS: ${messages.first}',
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 10. AUTOMATIC SMART MERGE DETECTOR (Fallback for Generic Snippets)
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
      final policy = clean.replaceFirst('restart:', '').replaceAll('"', '').trim();
      return mergeRestartPolicy(yaml, cursorOffset, policy);
    }

    // 3. Healthcheck
    if (clean.startsWith('healthcheck:') || snippet.contains('test:')) {
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

    // 9. DNS / CoreDNS
    if (clean.startsWith('dns:') || snippet.contains('dns:') || clean.startsWith('dns_search:')) {
      final dnsIPs = <String>[];
      final searchDoms = <String>[];
      for (final line in snippet.split('\n')) {
        final t = line.replaceAll('"', '').replaceAll("'", "").trim();
        if (t.startsWith('- ') && (t.contains('.') || t.contains('gbnt'))) {
          final val = t.substring(2).trim();
          if (RegExp(r'^[0-9\.]+$').hasMatch(val)) {
            dnsIPs.add(val);
          } else {
            searchDoms.add(val);
          }
        }
      }
      if (dnsIPs.isNotEmpty || searchDoms.isNotEmpty) {
        return mergeDNS(
          yaml,
          cursorOffset,
          dnsServers: dnsIPs.isEmpty ? ['192.168.252.39'] : dnsIPs,
          searchDomains: searchDoms.isEmpty ? ['gbnt.local', 'gbnt'] : searchDoms,
        );
      }
    }

    return null;
  }
}

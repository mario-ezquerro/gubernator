import 'package:flutter_test/flutter_test.dart';
import 'package:gubernator_web/utils/compose_smart_merger.dart';

void main() {
  group('ComposeSmartMerger - Singletons & In-Place Updates', () {
    const initialCompose = '''services:
  web:
    image: nginx:alpine
    ports:
      - "80:80"
''';

    test('Resources: Inserts deploy.resources when absent', () {
      final res = ComposeSmartMerger.mergeResources(
        initialCompose,
        0,
        cpuLimit: '1.0',
        memLimit: '512M',
        cpuReserve: '0.25',
        memReserve: '128M',
      );

      expect(res.action, equals(MergeActionType.inserted));
      expect(res.newYaml.contains('deploy:'), isTrue);
      expect(res.newYaml.contains('resources:'), isTrue);
      expect(res.newYaml.contains('cpus: "1.0"'), isTrue);
      expect(res.newYaml.contains('memory: 512M'), isTrue);
    });

    test('Resources: Updates existing resources in-place without duplicating blocks', () {
      // First insert 1.0 CPU / 512M
      final first = ComposeSmartMerger.mergeResources(
        initialCompose,
        0,
        cpuLimit: '1.0',
        memLimit: '512M',
        cpuReserve: '0.25',
        memReserve: '128M',
      );

      // Now update to 2.0 CPU / 2G (e.g. user clicks Database preset)
      final second = ComposeSmartMerger.mergeResources(
        first.newYaml,
        0,
        cpuLimit: '2.0',
        memLimit: '2G',
        cpuReserve: '0.5',
        memReserve: '512M',
      );

      expect(second.action, equals(MergeActionType.updated));
      expect(second.newYaml.contains('cpus: "2.0"'), isTrue);
      expect(second.newYaml.contains('memory: 2G'), isTrue);

      // Verify STRICTLY single occurrence of deploy: and resources:
      final deployMatches = RegExp(r'deploy:').allMatches(second.newYaml).length;
      final resMatches = RegExp(r'resources:').allMatches(second.newYaml).length;
      final limitsMatches = RegExp(r'limits:').allMatches(second.newYaml).length;

      expect(deployMatches, equals(1));
      expect(resMatches, equals(1));
      expect(limitsMatches, equals(1));
    });

    test('Resources: Detects alreadyExists if exact same limits applied', () {
      final first = ComposeSmartMerger.mergeResources(
        initialCompose,
        0,
        cpuLimit: '1.0',
        memLimit: '512M',
        cpuReserve: '0.25',
        memReserve: '128M',
      );

      final second = ComposeSmartMerger.mergeResources(
        first.newYaml,
        0,
        cpuLimit: '1.0',
        memLimit: '512M',
        cpuReserve: '0.25',
        memReserve: '128M',
      );

      expect(second.action, equals(MergeActionType.alreadyExists));
    });

    test('Restart Policy: Updates in-place without duplicate restart: lines', () {
      final first = ComposeSmartMerger.mergeRestartPolicy(initialCompose, 0, 'unless-stopped');
      expect(first.action, equals(MergeActionType.inserted));
      expect(first.newYaml.contains('restart: unless-stopped'), isTrue);

      final second = ComposeSmartMerger.mergeRestartPolicy(first.newYaml, 0, 'always');
      expect(second.action, equals(MergeActionType.updated));
      expect(second.newYaml.contains('restart: always'), isTrue);
      expect(second.newYaml.contains('restart: unless-stopped'), isFalse);

      final restartMatches = RegExp(r'restart:').allMatches(second.newYaml).length;
      expect(restartMatches, equals(1));

      final third = ComposeSmartMerger.mergeRestartPolicy(second.newYaml, 0, 'always');
      expect(third.action, equals(MergeActionType.alreadyExists));
    });

    test('Healthcheck: Updates in-place without duplicate healthcheck blocks', () {
      final first = ComposeSmartMerger.mergeHealthcheck(initialCompose, 0, testCmd: 'http://localhost:8080/health');
      expect(first.action, equals(MergeActionType.inserted));

      final second = ComposeSmartMerger.mergeHealthcheck(first.newYaml, 0, testCmd: 'http://localhost:3000/api/health');
      expect(second.action, equals(MergeActionType.updated));

      final hcMatches = RegExp(r'healthcheck:').allMatches(second.newYaml).length;
      expect(hcMatches, equals(1));
    });

    test('Placement Constraints: Updates node.role and node.hostname in-place', () {
      final first = ComposeSmartMerger.mergePlacementConstraint(
        initialCompose,
        0,
        constraint: 'node.role == worker',
        replacePrefix: 'node.role ==',
      );
      expect(first.action, equals(MergeActionType.inserted));
      expect(first.newYaml.contains('node.role == worker'), isTrue);

      // Switching to manager should update in-place, NOT append a second conflicting role
      final second = ComposeSmartMerger.mergePlacementConstraint(
        first.newYaml,
        0,
        constraint: 'node.role == manager',
        replacePrefix: 'node.role ==',
      );
      expect(second.action, equals(MergeActionType.updated));
      expect(second.newYaml.contains('node.role == manager'), isTrue);
      expect(second.newYaml.contains('node.role == worker'), isFalse);

      // Appending a pinned node hostname should coexist under the same constraints block
      final third = ComposeSmartMerger.mergePlacementConstraint(
        second.newYaml,
        0,
        constraint: 'node.hostname == centurion-node-1',
        replacePrefix: 'node.hostname ==',
      );
      expect(third.action, equals(MergeActionType.added));
      expect(third.newYaml.contains('node.role == manager'), isTrue);
      expect(third.newYaml.contains('node.hostname == centurion-node-1'), isTrue);

      final deployCount = RegExp(r'deploy:').allMatches(third.newYaml).length;
      final constraintsCount = RegExp(r'constraints:').allMatches(third.newYaml).length;
      expect(deployCount, equals(1));
      expect(constraintsCount, equals(1));
    });

    test('Labels: In-place update for existing keys and appends new keys', () {
      final first = ComposeSmartMerger.mergeLabels(
        initialCompose,
        0,
        const [
          MapEntry('ingress.host', 'app.gbnt.local'),
          MapEntry('gbnt.caddy.port', '80'),
        ],
      );
      expect(first.action, equals(MergeActionType.inserted));

      // Update port to 443
      final second = ComposeSmartMerger.mergeLabels(
        first.newYaml,
        0,
        const [
          MapEntry('gbnt.caddy.port', '443'),
        ],
      );
      expect(second.action, equals(MergeActionType.updated));
      expect(second.newYaml.contains('gbnt.caddy.port=443'), isTrue);
      expect(second.newYaml.contains('gbnt.caddy.port=80'), isFalse);

      final labelsCount = RegExp(r'labels:').allMatches(second.newYaml).length;
      expect(labelsCount, equals(1));
    });
  });

  group('ComposeSmartMerger - Collections & Deduplication', () {
    const initialCompose = '''services:
  web:
    image: nginx:alpine
    ports:
      - "80:80"
    volumes:
      - /var/contenedores/app/data:/data
''';

    test('Volumes: Appends new mount and prevents duplicates', () {
      // Adding a new volume mount
      final first = ComposeSmartMerger.mergeVolumeMount(
        initialCompose,
        0,
        './config.yml:/etc/config.yml:ro',
      );
      expect(first.action, equals(MergeActionType.added));
      expect(first.newYaml.contains('./config.yml:/etc/config.yml:ro'), isTrue);

      final volumesCount = RegExp(r'volumes:').allMatches(first.newYaml).length;
      expect(volumesCount, equals(1));

      // Adding the EXACT same volume mount again
      final second = ComposeSmartMerger.mergeVolumeMount(
        first.newYaml,
        0,
        './config.yml:/etc/config.yml:ro',
      );
      expect(second.action, equals(MergeActionType.alreadyExists));
      expect(second.message.contains('already configured'), isTrue);
    });

    test('Ports: Appends new ports and prevents duplicates', () {
      // Trying to add 80:80 which already exists
      final first = ComposeSmartMerger.mergePorts(initialCompose, 0, ['80:80']);
      expect(first.action, equals(MergeActionType.alreadyExists));

      // Adding new port 443:443
      final second = ComposeSmartMerger.mergePorts(initialCompose, 0, ['443:443']);
      expect(second.action, equals(MergeActionType.added));
      expect(second.newYaml.contains('"443:443"'), isTrue);

      final portsCount = RegExp(r'ports:').allMatches(second.newYaml).length;
      expect(portsCount, equals(1));
    });

    test('Environment: Updates existing keys and appends new keys', () {
      const envCompose = '''services:
  web:
    image: nginx:alpine
    environment:
      - NODE_ENV=development
      - PORT=3000
''';

      final res = ComposeSmartMerger.mergeEnvironment(
        envCompose,
        0,
        const [
          MapEntry('NODE_ENV', 'production'),
          MapEntry('LOG_LEVEL', 'debug'),
        ],
      );

      expect(res.action, equals(MergeActionType.updated));
      expect(res.newYaml.contains('NODE_ENV=production'), isTrue);
      expect(res.newYaml.contains('NODE_ENV=development'), isFalse);
      expect(res.newYaml.contains('LOG_LEVEL=debug'), isTrue);
      expect(res.newYaml.contains('PORT=3000'), isTrue);

      final envCount = RegExp(r'environment:').allMatches(res.newYaml).length;
      expect(envCount, equals(1));
    });
  });

  group('ComposeSmartMerger - trySmartMerge Fallback Detector', () {
    const initialCompose = '''services:
  web:
    image: nginx:alpine
''';

    test('Detects and smart-merges resources snippet', () {
      const snippet = '''    deploy:
      resources:
        limits:
          cpus: "1.5"
          memory: 1G
''';
      final res = ComposeSmartMerger.trySmartMerge(initialCompose, 0, snippet);
      expect(res, isNotNull);
      expect(res!.action, equals(MergeActionType.inserted));
      expect(res.newYaml.contains('cpus: "1.5"'), isTrue);
    });

    test('Detects and smart-merges restart policy snippet', () {
      const snippet = '    restart: unless-stopped\n';
      final res = ComposeSmartMerger.trySmartMerge(initialCompose, 0, snippet);
      expect(res, isNotNull);
      expect(res!.action, equals(MergeActionType.inserted));
      expect(res.newYaml.contains('restart: unless-stopped'), isTrue);
    });

    test('Detects and smart-merges volume snippet with deduplication', () {
      const snippet = '      - /var/contenedores/\${STACK_NAME}/data:/data\n';
      final res = ComposeSmartMerger.trySmartMerge(initialCompose, 0, snippet);
      expect(res, isNotNull);
      expect(res!.newYaml.contains('/var/contenedores/\${STACK_NAME}/data:/data'), isTrue);
    });
  });
}

import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../utils/clipboard_service.dart';

/// Enhanced Add Centurion (Host) Dialog with 3 Tabs:
/// 1. ⚡ Quick Join (Copy & Paste Commands)
/// 2. 🚀 Remote SSH Provisioning + Live Terminal Console
/// 3. ☁️ Cloud-Init & Automation (IaC)
class AddNodeDialog extends StatefulWidget {
  final DashboardState state;
  final VoidCallback onNodeAdded;

  const AddNodeDialog({
    super.key,
    required this.state,
    required this.onNodeAdded,
  });

  @override
  State<AddNodeDialog> createState() => _AddNodeDialogState();
}

class _AddNodeDialogState extends State<AddNodeDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  NodeJoinInfo? _joinInfo;
  bool _loadingInfo = true;

  // Form Controllers
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _portController = TextEditingController(text: '22');
  final TextEditingController _userController = TextEditingController(text: 'ubuntu');
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _privateKeyController = TextEditingController();

  String _authType = 'password'; // 'password', 'private_key', 'manager_key'
  bool _deploySystemStacks = true;

  // Provisioning State
  bool _isProvisioning = false;
  NodeProvisionResult? _provisionResult;
  String? _provisionError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadJoinInfo();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _userController.dispose();
    _passwordController.dispose();
    _privateKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadJoinInfo() async {
    final info = await ApiService.fetchJoinInfo();
    if (mounted) {
      setState(() {
        _joinInfo = info;
        _loadingInfo = false;
      });
    }
  }

  void _copyToClipboard(String text, String label) {
    ClipboardService.copy(text);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied $label to clipboard!'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _startProvisioning() async {
    final host = _hostController.text.trim();
    final user = _userController.text.trim();
    final port = _portController.text.trim().isEmpty ? '22' : _portController.text.trim();

    if (host.isEmpty) {
      setState(() => _provisionError = 'Host IP or FQDN is required');
      return;
    }
    if (user.isEmpty) {
      setState(() => _provisionError = 'SSH Username is required');
      return;
    }
    if (_authType == 'password' && _passwordController.text.isEmpty) {
      setState(() => _provisionError = 'SSH Password is required for Password Authentication');
      return;
    }
    if (_authType == 'private_key' && _privateKeyController.text.trim().isEmpty) {
      setState(() => _provisionError = 'SSH Private Key (PEM) is required');
      return;
    }

    setState(() {
      _isProvisioning = true;
      _provisionError = null;
      _provisionResult = null;
    });

    final result = await ApiService.provisionNode(
      host: host,
      port: port,
      user: user,
      authType: _authType,
      password: _passwordController.text,
      privateKey: _privateKeyController.text,
      deploySystemStacks: _deploySystemStacks,
    );

    if (mounted) {
      setState(() {
        _isProvisioning = false;
        _provisionResult = result;
        if (!result.success) {
          _provisionError = result.error ?? result.message;
        }
      });
      if (result.success) {
        widget.onNodeAdded();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final managerIp = _joinInfo?.managerIp.isNotEmpty == true
        ? _joinInfo!.managerIp
        : widget.state.managerIp.isNotEmpty
            ? widget.state.managerIp
            : '192.168.252.31';
    final managerHttp = 'http://$managerIp:4000';
    final webHttp = 'http://$managerIp:4001';
    final joinToken = _joinInfo?.joinToken.isNotEmpty == true
        ? _joinInfo!.joinToken
        : widget.state.clusterJoinToken;
    final apiToken = _joinInfo?.apiToken.isNotEmpty == true
        ? _joinInfo!.apiToken
        : widget.state.activeApiToken;

    final oneLinerCmd = _joinInfo?.oneLinerCmd.isNotEmpty == true
        ? _joinInfo!.oneLinerCmd
        : 'curl -fsSL $webHttp/api/node/join.sh | sudo bash -s -- --manager $managerHttp --token $joinToken --api-token $apiToken';

    final dockerCmd = _joinInfo?.dockerCmd.isNotEmpty == true
        ? _joinInfo!.dockerCmd
        : 'sudo docker run -d --name gbnt-worker --network host --restart unless-stopped -v /var/run/docker.sock:/var/run/docker.sock -v /data:/data marioezquerro/gubernator:latest legion join --token $joinToken --manager $managerHttp --api-token $apiToken';

    final cliCmd = _joinInfo?.cliCmd.isNotEmpty == true
        ? _joinInfo!.cliCmd
        : 'sudo gbnt legion join --token $joinToken --manager $managerHttp --api-token $apiToken';

    final cloudInitYaml = _joinInfo?.cloudInitYaml.isNotEmpty == true
        ? _joinInfo!.cloudInitYaml
        : '''#cloud-config
package_upgrade: true
packages:
  - curl
  - docker.io
runcmd:
  - systemctl enable --now docker
  - $dockerCmd
''';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 820,
        height: 680,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ─── Header ──────────────────────────────────────────
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.dns_rounded, color: Color(0xFF10B981), size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add Centurion Worker Host',
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Choose your preferred onboarding method: instant copy-paste, remote SSH provision, or cloud-init.',
                        style: TextStyle(fontSize: 12.5, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ─── Tab Bar ─────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                indicator: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.primary.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                labelColor: Colors.white,
                unselectedLabelColor: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                tabs: const [
                  Tab(icon: Icon(Icons.bolt, size: 18), text: '⚡ Quick Join (Copy & Paste)'),
                  Tab(icon: Icon(Icons.terminal, size: 18), text: '🚀 Remote SSH Provision'),
                  Tab(icon: Icon(Icons.cloud_outlined, size: 18), text: '☁️ Cloud-Init & Automation'),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ─── Tab Views ───────────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: Quick Join
                  _buildQuickJoinTab(theme, isDark, managerIp, joinToken, oneLinerCmd, dockerCmd, cliCmd),

                  // Tab 2: Remote SSH Provision
                  _buildSshProvisionTab(theme, isDark),

                  // Tab 3: Cloud-Init & Automation
                  _buildCloudInitTab(theme, isDark, cloudInitYaml),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── TAB 1: Quick Join ─────────────────────────────────────────
  Widget _buildQuickJoinTab(
    ThemeData theme,
    bool isDark,
    String managerIp,
    String joinToken,
    String oneLinerCmd,
    String dockerCmd,
    String cliCmd,
  ) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Step-by-Step Info Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No SSH configuration or passwords needed! Open a terminal on your new machine, '
                    'paste any of the commands below, and the Centurion worker will immediately register into the cluster.',
                    style: TextStyle(fontSize: 12.5, color: theme.colorScheme.onSurface),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Option 1: One-Liner Auto Installer
          _buildCommandCard(
            theme: theme,
            isDark: isDark,
            badgeText: 'RECOMMENDED • FASTEST',
            badgeColor: const Color(0xFF10B981),
            title: '1. One-Liner Automated Installer (Script)',
            description: 'Installs Docker CE if missing, configures systemd persistence, and starts the Centurion worker agent.',
            command: oneLinerCmd,
            onCopy: () => _copyToClipboard(oneLinerCmd, 'One-Liner Command'),
          ),
          const SizedBox(height: 14),

          // Option 2: Docker Container
          _buildCommandCard(
            theme: theme,
            isDark: isDark,
            badgeText: 'DOCKER CONTAINER',
            badgeColor: const Color(0xFF3B82F6),
            title: '2. Docker Container (Native Engine)',
            description: 'Runs the Gubernator Centurion worker as an isolated Docker container with host network privileges.',
            command: dockerCmd,
            onCopy: () => _copyToClipboard(dockerCmd, 'Docker Command'),
          ),
          const SizedBox(height: 14),

          // Option 3: Gubernator CLI Binary
          _buildCommandCard(
            theme: theme,
            isDark: isDark,
            badgeText: 'STANDALONE BINARY',
            badgeColor: const Color(0xFF8B5CF6),
            title: '3. Gubernator CLI Binary',
            description: 'Use when the `gbnt` binary is already installed in `/usr/local/bin/gbnt`.',
            command: cliCmd,
            onCopy: () => _copyToClipboard(cliCmd, 'CLI Command'),
          ),
          const SizedBox(height: 16),

          // Live Cluster Pulse Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF10B981),
                    boxShadow: [
                      BoxShadow(color: Color(0xFF10B981), blurRadius: 6),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Cluster Manager: $managerIp:4000  •  ${widget.state.nodes.length} Centurions Registered',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                  ),
                ),
                const Spacer(),
                Text(
                  'Auto-refreshing state every 5s',
                  style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── TAB 2: Remote SSH Provision & Live Console ────────────────
  Widget _buildSshProvisionTab(ThemeData theme, bool isDark) {
    if (_isProvisioning || _provisionResult != null) {
      return _buildLiveProvisionConsole(theme, isDark);
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_provisionError != null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: theme.colorScheme.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colorScheme.error.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: theme.colorScheme.error, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _provisionError!,
                      style: TextStyle(color: theme.colorScheme.error, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Form: Host & Port
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _hostController,
                  decoration: const InputDecoration(
                    labelText: 'Target Host IP / FQDN *',
                    hintText: 'e.g. 192.168.252.34 or worker3.local',
                    prefixIcon: Icon(Icons.computer, size: 20),
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 1,
                child: TextField(
                  controller: _portController,
                  decoration: const InputDecoration(
                    labelText: 'SSH Port',
                    hintText: '22',
                    prefixIcon: Icon(Icons.tag, size: 18),
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Form: Username
          TextField(
            controller: _userController,
            decoration: const InputDecoration(
              labelText: 'SSH Username *',
              hintText: 'ubuntu / root / debian',
              prefixIcon: Icon(Icons.person, size: 20),
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          const SizedBox(height: 14),

          // Authentication Mode Segmented Buttons
          const Text('SSH Authentication Method *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'password',
                label: Text('Password'),
                icon: Icon(Icons.password, size: 16),
              ),
              ButtonSegment(
                value: 'private_key',
                label: Text('Private Key (.pem)'),
                icon: Icon(Icons.key, size: 16),
              ),
              ButtonSegment(
                value: 'manager_key',
                label: Text('Manager SSH Key'),
                icon: Icon(Icons.vpn_key_outlined, size: 16),
              ),
            ],
            selected: {_authType},
            onSelectionChanged: (val) => setState(() => _authType = val.first),
          ),
          const SizedBox(height: 12),

          // Dynamic Auth Inputs
          if (_authType == 'password') ...[
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'SSH Password / Sudo Password *',
                hintText: 'Enter password for SSH & sudo privilege elevation',
                prefixIcon: Icon(Icons.lock, size: 20),
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ] else if (_authType == 'private_key') ...[
            TextField(
              controller: _privateKeyController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'SSH Private Key (RSA / ED25519 / PEM) *',
                hintText: '-----BEGIN OPENSSH PRIVATE KEY-----\n...\n-----END OPENSSH PRIVATE KEY-----',
                prefixIcon: Icon(Icons.shield, size: 20),
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ] else if (_authType == 'manager_key') ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.vpn_key_outlined, size: 18, color: Color(0xFF10B981)),
                      const SizedBox(width: 8),
                      const Text('Manager Public Key:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 16),
                        tooltip: 'Copy Public Key',
                        onPressed: () {
                          final pubKey = _joinInfo?.managerPublicKey ?? '';
                          if (pubKey.isNotEmpty) {
                            _copyToClipboard(pubKey, 'Manager Public Key');
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    _joinInfo?.managerPublicKey.isNotEmpty == true
                        ? _joinInfo!.managerPublicKey
                        : 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... (Auto-discovered from Manager)',
                    style: const TextStyle(fontFamily: 'Courier New', fontSize: 11),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Ensure this public key is appended to /home/ubuntu/.ssh/authorized_keys on the remote worker host.',
                    style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),

          // Options: Auto deploy system stacks
          SwitchListTile(
            value: _deploySystemStacks,
            onChanged: (val) => setState(() => _deploySystemStacks = val),
            title: const Text('Auto-deploy System Stacks (CORE Caddy & SRE Monitor)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: const Text('Automatically bootstrap Caddy reverse proxy and Prometheus monitoring agents on join.', style: TextStyle(fontSize: 11.5)),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 16),

          // Provision Action Button
          FilledButton.icon(
            onPressed: _startProvisioning,
            icon: const Icon(Icons.rocket_launch, size: 18),
            label: const Text('Start Remote SSH Provisioning', style: TextStyle(fontWeight: FontWeight.bold)),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Live Terminal Console ────────────────────────────────────
  Widget _buildLiveProvisionConsole(ThemeData theme, bool isDark) {
    final result = _provisionResult;
    final logs = result?.logs ?? [];

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Console Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
              borderRadius: BorderRadius.vertical(top: Radius.circular(9)),
            ),
            child: Row(
              children: [
                Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFFF59E0B), shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle)),
                const SizedBox(width: 12),
                Text(
                  'Centurion Provisioning Console — ${_hostController.text.trim()}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'Courier New', fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_isProvisioning) ...[
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF10B981)),
                  ),
                  const SizedBox(width: 8),
                  const Text('Executing...', style: TextStyle(color: Color(0xFF10B981), fontSize: 11)),
                ],
              ],
            ),
          ),

          // Console Body
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('🏛️ GUBERNATOR REMOTE PROVISIONING ENGINE v2.59', style: TextStyle(color: Color(0xFF64748B), fontSize: 11, fontFamily: 'Courier New')),
                  const SizedBox(height: 8),
                  if (_isProvisioning && logs.isEmpty) ...[
                    _buildConsoleStep(
                      step: 'SSH Connection',
                      message: 'Connecting to ${_hostController.text}:${_portController.text} as user \'${_userController.text}\'...',
                      status: 'running',
                    ),
                  ],
                  ...logs.map((l) => _buildConsoleStep(step: l.step, message: l.message, status: l.status)),
                  if (result != null && result.success) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.check_circle, color: Color(0xFF10B981), size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '🎉 SUCCESS: Centurion worker host is online and active in cluster!',
                              style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'Courier New'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (result != null && !result.success) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        '❌ ERROR: ${result.error ?? result.message}',
                        style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12, fontFamily: 'Courier New'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Console Footer Controls
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(9)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!_isProvisioning) ...[
                  TextButton(
                    onPressed: () => setState(() {
                      _isProvisioning = false;
                      _provisionResult = null;
                      _provisionError = null;
                    }),
                    child: const Text('← Back to Form', style: TextStyle(color: Colors.white70)),
                  ),
                  const SizedBox(width: 8),
                ],
                FilledButton(
                  onPressed: _isProvisioning ? null : () => Navigator.of(context).pop(),
                  child: Text(result?.success == true ? 'Done' : 'Close'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConsoleStep({required String step, required String message, required String status}) {
    Color color = Colors.white70;
    Widget icon = const SizedBox.shrink();

    if (status == 'ok') {
      color = const Color(0xFF34D399);
      icon = const Icon(Icons.check, size: 14, color: Color(0xFF34D399));
    } else if (status == 'error') {
      color = const Color(0xFFF87171);
      icon = const Icon(Icons.close, size: 14, color: Color(0xFFF87171));
    } else if (status == 'warn') {
      color = const Color(0xFFFBBF24);
      icon = const Icon(Icons.warning_amber, size: 14, color: Color(0xFFFBBF24));
    } else if (status == 'running') {
      color = const Color(0xFF60A5FA);
      icon = const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF60A5FA)));
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 18, child: icon),
          const SizedBox(width: 6),
          Text('[$step] ', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11.5, fontFamily: 'Courier New')),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontFamily: 'Courier New'),
            ),
          ),
        ],
      ),
    );
  }

  // ─── TAB 3: Cloud-Init & Automation ───────────────────────────
  Widget _buildCloudInitTab(ThemeData theme, bool isDark, String cloudInitYaml) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF8B5CF6).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.25)),
            ),
            child: const Row(
              children: [
                Icon(Icons.cloud_circle, color: Color(0xFF8B5CF6), size: 22),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Use this Cloud-Init YAML blueprint to automate worker provisioning in Proxmox VE, '
                    'Hetzner Cloud, AWS EC2 User Data, GCP, or OpenStack on first boot.',
                    style: TextStyle(fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          _buildCommandCard(
            theme: theme,
            isDark: isDark,
            badgeText: 'CLOUD-CONFIG YAML',
            badgeColor: const Color(0xFF8B5CF6),
            title: 'Automated Cloud-Init Configuration',
            description: 'Paste into your VM template or cloud instance UserData field.',
            command: cloudInitYaml,
            onCopy: () => _copyToClipboard(cloudInitYaml, 'Cloud-Init YAML'),
          ),
        ],
      ),
    );
  }

  // ─── Reusable Command Card ────────────────────────────────────
  Widget _buildCommandCard({
    required ThemeData theme,
    required bool isDark,
    required String badgeText,
    required Color badgeColor,
    required String title,
    required String description,
    required String command,
    required VoidCallback onCopy,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(color: badgeColor, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 16),
                tooltip: 'Copy command',
                style: IconButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
                  foregroundColor: theme.colorScheme.primary,
                ),
                onPressed: onCopy,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: TextStyle(fontSize: 11.5, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 10),

          // Code Container
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: SelectableText(
              command,
              style: const TextStyle(
                fontFamily: 'Courier New',
                fontSize: 11.5,
                color: Color(0xFF38BDF8),
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

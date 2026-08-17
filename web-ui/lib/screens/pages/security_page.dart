import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../utils/clipboard_service.dart';

class SecurityPage extends StatefulWidget {
  final DashboardState state;
  final VoidCallback onRefresh;

  const SecurityPage({
    super.key,
    required this.state,
    required this.onRefresh,
  });

  @override
  State<SecurityPage> createState() => _SecurityPageState();
}

class _SecurityPageState extends State<SecurityPage> {
  List<LDAPConfig> _ldapConfigs = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLDAPConfigs();
  }

  Future<void> _loadLDAPConfigs() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final configs = await ApiService.fetchLDAPConfigs();
      if (mounted) {
        setState(() {
          _ldapConfigs = configs;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : null,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _openLDAPDialog([LDAPConfig? config]) {
    final isEdit = config != null;
    final nameCtrl = TextEditingController(text: config?.name ?? 'Corporate Active Directory');
    final hostCtrl = TextEditingController(text: config?.host ?? '');
    final portCtrl = TextEditingController(text: (config?.port ?? 389).toString());
    final baseDnCtrl = TextEditingController(text: config?.baseDn ?? 'DC=corp,DC=local');
    final bindDnCtrl = TextEditingController(text: config?.bindDn ?? '');
    final bindPassCtrl = TextEditingController(text: config?.bindPassword ?? '');
    final userFilterCtrl = TextEditingController(text: config?.userFilter ?? '(&(objectClass=user)(sAMAccountName=%s))');
    final userAttrCtrl = TextEditingController(text: config?.userAttr ?? 'sAMAccountName');
    final groupBaseDnCtrl = TextEditingController(text: config?.groupBaseDn ?? '');
    final adminGroupCtrl = TextEditingController(text: config?.adminGroupDn ?? 'CN=Gubernator_Admins,OU=Groups,DC=corp,DC=local');
    final operatorGroupCtrl = TextEditingController(text: config?.operatorGroupDn ?? 'CN=Gubernator_Operators,OU=Groups,DC=corp,DC=local');
    final readOnlyGroupCtrl = TextEditingController(text: config?.readOnlyGroupDn ?? 'CN=Gubernator_Viewers,OU=Groups,DC=corp,DC=local');

    String security = config?.security ?? 'none';
    bool insecureSkipVerify = config?.insecureSkipVerify ?? false;
    bool enabled = config?.enabled ?? true;
    String defaultRole = config?.defaultRole ?? 'readonly';

    bool testing = false;
    LDAPTestResult? testResult;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;

          return AlertDialog(
            title: Row(
              children: [
                Icon(
                  isEdit ? Icons.edit_note : Icons.add_moderator,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Text(isEdit ? 'Edit Directory Server' : 'Add Active Directory / LDAP Server'),
              ],
            ),
            content: SizedBox(
              width: 680,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // General info
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: nameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Display Name *',
                              hintText: 'e.g. Corporate Active Directory',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SwitchListTile(
                            title: const Text('Enabled', style: TextStyle(fontSize: 13)),
                            value: enabled,
                            onChanged: (v) => setDialogState(() => enabled = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Host & Port & Security
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: hostCtrl,
                            decoration: const InputDecoration(
                              labelText: 'LDAP Host / IP *',
                              hintText: 'dc1.company.local',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: portCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Port',
                              hintText: '389 / 636',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: security,
                            decoration: const InputDecoration(labelText: 'Security Mode'),
                            items: const [
                              DropdownMenuItem(value: 'none', child: Text('None (389)')),
                              DropdownMenuItem(value: 'tls', child: Text('LDAPS / TLS (636)')),
                              DropdownMenuItem(value: 'starttls', child: Text('StartTLS')),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                setDialogState(() {
                                  security = v;
                                  if (v == 'tls' && portCtrl.text == '389') {
                                    portCtrl.text = '636';
                                  } else if (v == 'none' && portCtrl.text == '636') {
                                    portCtrl.text = '389';
                                  }
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Insecure Skip Verify (Accept self-signed domain certificates)', style: TextStyle(fontSize: 12.5)),
                      value: insecureSkipVerify,
                      onChanged: (v) => setDialogState(() => insecureSkipVerify = v ?? false),
                    ),
                    const Divider(height: 24),

                    // Search Base & Service Account
                    const Text('Search Credentials (Service Account)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: baseDnCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Base DN (Search Base) *',
                        hintText: 'DC=company,DC=local',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: bindDnCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Bind DN / Service User',
                              hintText: 'CN=svc_gubernator,OU=ServiceAccounts,DC=company,DC=local',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: bindPassCtrl,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'Bind Password',
                              hintText: '••••••••',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),

                    // User Filter
                    const Text('User Search Filter', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: userFilterCtrl,
                            decoration: const InputDecoration(
                              labelText: 'User Filter Query',
                              hintText: '(&(objectClass=user)(sAMAccountName=%s))',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: userAttrCtrl,
                            decoration: const InputDecoration(
                              labelText: 'User Attribute',
                              hintText: 'sAMAccountName / uid',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),

                    // RBAC Group Mappings
                    const Text('Group Mappings to RBAC Roles (Gubernator)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: adminGroupCtrl,
                      decoration: const InputDecoration(
                        labelText: '👑 Group for ADMIN Role (Full Access)',
                        hintText: 'CN=Gubernator_Admins,OU=Groups,DC=company,DC=local',
                        prefixIcon: Icon(Icons.admin_panel_settings, color: Colors.amber, size: 20),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: operatorGroupCtrl,
                      decoration: const InputDecoration(
                        labelText: '⚡ Group for OPERATOR Role (Deploy & Restart)',
                        hintText: 'CN=Gubernator_Operators,OU=Groups,DC=company,DC=local',
                        prefixIcon: Icon(Icons.engineering, color: Colors.blue, size: 20),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: readOnlyGroupCtrl,
                      decoration: const InputDecoration(
                        labelText: '👁️ Group for READ-ONLY Role (Viewer)',
                        hintText: 'CN=Gubernator_Viewers,OU=Groups,DC=company,DC=local',
                        prefixIcon: Icon(Icons.visibility, color: Colors.green, size: 20),
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: defaultRole,
                      decoration: const InputDecoration(labelText: 'Default Fallback Role (if no group matches)'),
                      items: const [
                        DropdownMenuItem(value: 'readonly', child: Text('👁️ Read-Only (Recommended)')),
                        DropdownMenuItem(value: 'operator', child: Text('⚡ Operator')),
                        DropdownMenuItem(value: 'admin', child: Text('👑 Administrator')),
                      ],
                      onChanged: (v) {
                        if (v != null) setDialogState(() => defaultRole = v);
                      },
                    ),
                    const SizedBox(height: 16),

                    // Diagnostic Test Output
                    if (testResult != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: testResult!.connected
                              ? (testResult!.bindSuccessful ? Colors.green.withValues(alpha: 0.1) : Colors.amber.withValues(alpha: 0.1))
                              : Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: testResult!.connected
                                ? (testResult!.bindSuccessful ? Colors.green.withValues(alpha: 0.3) : Colors.amber.withValues(alpha: 0.3))
                                : Colors.red.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  testResult!.connected ? (testResult!.bindSuccessful ? Icons.check_circle : Icons.warning) : Icons.error,
                                  color: testResult!.connected ? (testResult!.bindSuccessful ? Colors.green : Colors.amber) : Colors.red,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  testResult!.connected ? 'Connection Test: Successful (${testResult!.latencyMs} ms)' : 'Connection Test: Failed',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: testResult!.connected ? (testResult!.bindSuccessful ? Colors.green : Colors.amber) : Colors.red,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              testResult!.message,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              // Test Connection button
              OutlinedButton.icon(
                icon: testing
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.network_check, size: 16),
                label: const Text('Test Connection'),
                onPressed: testing
                    ? null
                    : () async {
                        final host = hostCtrl.text.trim();
                        final baseDn = baseDnCtrl.text.trim();
                        if (host.isEmpty || baseDn.isEmpty) {
                          _showSnackBar('Host and Base DN are required to test connection', isError: true);
                          return;
                        }

                        setDialogState(() {
                          testing = true;
                          testResult = null;
                        });

                        final cfg = LDAPConfig(
                          id: config?.id ?? 'test',
                          name: nameCtrl.text.trim(),
                          enabled: enabled,
                          host: host,
                          port: int.tryParse(portCtrl.text) ?? 389,
                          security: security,
                          insecureSkipVerify: insecureSkipVerify,
                          bindDn: bindDnCtrl.text.trim(),
                          bindPassword: bindPassCtrl.text,
                          baseDn: baseDn,
                          userFilter: userFilterCtrl.text.trim(),
                          userAttr: userAttrCtrl.text.trim(),
                          groupBaseDn: groupBaseDnCtrl.text.trim(),
                          adminGroupDn: adminGroupCtrl.text.trim(),
                          operatorGroupDn: operatorGroupCtrl.text.trim(),
                          readOnlyGroupDn: readOnlyGroupCtrl.text.trim(),
                          defaultRole: defaultRole,
                        );

                        final res = await ApiService.testLDAPConfig(cfg);
                        setDialogState(() {
                          testing = false;
                          testResult = res;
                        });
                      },
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final name = nameCtrl.text.trim();
                  final host = hostCtrl.text.trim();
                  final baseDn = baseDnCtrl.text.trim();

                  if (name.isEmpty || host.isEmpty || baseDn.isEmpty) {
                    _showSnackBar('Please fill all required fields (*)', isError: true);
                    return;
                  }

                  final cfg = LDAPConfig(
                    id: config?.id ?? '',
                    name: name,
                    enabled: enabled,
                    host: host,
                    port: int.tryParse(portCtrl.text) ?? 389,
                    security: security,
                    insecureSkipVerify: insecureSkipVerify,
                    bindDn: bindDnCtrl.text.trim(),
                    bindPassword: bindPassCtrl.text,
                    baseDn: baseDn,
                    userFilter: userFilterCtrl.text.trim(),
                    userAttr: userAttrCtrl.text.trim(),
                    groupBaseDn: groupBaseDnCtrl.text.trim(),
                    adminGroupDn: adminGroupCtrl.text.trim(),
                    operatorGroupDn: operatorGroupCtrl.text.trim(),
                    readOnlyGroupDn: readOnlyGroupCtrl.text.trim(),
                    defaultRole: defaultRole,
                  );

                  final res = await ApiService.saveLDAPConfig(cfg);
                  if (res['error'] != null) {
                    _showSnackBar('Failed to save directory config: ${res['error']}', isError: true);
                    return;
                  }

                  Navigator.pop(ctx);
                  _showSnackBar('Directory server configuration saved');
                  _loadLDAPConfigs();
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteLDAP(LDAPConfig config) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Directory Server'),
        content: Text('Are you sure you want to remove "${config.name}"? Users from this domain will no longer be able to authenticate.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final ok = await ApiService.deleteLDAPConfig(config.id);
      if (ok) {
        _showSnackBar('Directory server removed');
        _loadLDAPConfigs();
      } else {
        _showSnackBar('Failed to remove directory server', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return RefreshIndicator(
      onRefresh: () async {
        await _loadLDAPConfigs();
        widget.onRefresh();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Page Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.shield_outlined, color: primaryColor, size: 28),
                        const SizedBox(width: 10),
                        const Text(
                          'Security & Directory Services',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Enterprise directory authentication, Active Directory/LDAP servers, and RBAC access policies.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Directory Server (AD / LDAP)'),
                  onPressed: () => _openLDAPDialog(),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Active Providers Overview Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Identities & Access Control (RBAC)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  Text(
                    'Gubernator supports dual authentication: an emergency Local Administrator account and multiple Active Directory / OpenLDAP servers with dynamic group mapping to Administrator, Operator, and Read-Only roles.',
                    style: TextStyle(fontSize: 13, height: 1.4, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _buildRoleBadge('👑 Administrator', 'Full access (Deploy/Destroy/Nodes/Caddy/Security)', Colors.amber),
                      _buildRoleBadge('⚡ Operator', 'Deploy and restart stacks, without cluster infrastructure mutations', Colors.blue),
                      _buildRoleBadge('👁️ Read-Only', 'Audit and monitoring (Pure visualization without destructive actions)', Colors.green),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Configured LDAP Servers List
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Connected Active Directory / LDAP Servers',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: 'Refresh',
                  onPressed: _loadLDAPConfigs,
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (_loading)
              const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
            else if (_error != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Text('Error loading directory servers: $_error', style: const TextStyle(color: Colors.red)),
              )
            else if (_ldapConfigs.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B).withValues(alpha: 0.5) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.withValues(alpha: 0.2)),
                ),
                child: Column(
                  children: [
                    Icon(Icons.corporate_fare_outlined, size: 48, color: Colors.grey.withValues(alpha: 0.5)),
                    const SizedBox(height: 12),
                    const Text('No Active Directory / LDAP servers configured', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 6),
                    const Text('Currently the cluster is using the Local Administrator account (admin / admin).', style: TextStyle(fontSize: 13, color: Colors.grey)),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Connect First Active Directory'),
                      onPressed: () => _openLDAPDialog(),
                    ),
                  ],
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _ldapConfigs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final cfg = _ldapConfigs[index];
                  return Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.security, color: Color(0xFF38BDF8), size: 24),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(cfg.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                  const SizedBox(width: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: cfg.enabled ? Colors.green.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      cfg.enabled ? 'ACTIVE' : 'DISABLED',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                        color: cfg.enabled ? Colors.green : Colors.grey,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      cfg.security.toUpperCase(),
                                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.blue),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${cfg.host}:${cfg.port} (Base DN: ${cfg.baseDn})',
                                style: TextStyle(fontFamily: 'Courier New', fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  if (cfg.adminGroupDn.isNotEmpty) _buildGroupChip('👑 Admin', cfg.adminGroupDn, Colors.amber),
                                  if (cfg.operatorGroupDn.isNotEmpty) _buildGroupChip('⚡ Ops', cfg.operatorGroupDn, Colors.blue),
                                  if (cfg.readOnlyGroupDn.isNotEmpty) _buildGroupChip('👁️ View', cfg.readOnlyGroupDn, Colors.green),
                                  _buildGroupChip('Default', cfg.defaultRole.toUpperCase(), Colors.grey),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          tooltip: 'Edit',
                          onPressed: () => _openLDAPDialog(cfg),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                          tooltip: 'Delete',
                          onPressed: () => _deleteLDAP(cfg),
                        ),
                      ],
                    ),
                  );
                },
              ),
            const SizedBox(height: 32),

            // Emergency Local Token Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.key, color: Colors.orange, size: 22),
                      const SizedBox(width: 10),
                      const Text('Cluster Security Tokens & CLI Access', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Cryptographic tokens used for asymmetric REST API authentication (Port 4000) and `gbnt legion join` commands.',
                    style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65)),
                  ),
                  const SizedBox(height: 16),
                  _buildTokenRow('Active API Token (GBNT_API_TOKEN)', widget.state.activeApiToken, isDark),
                  const SizedBox(height: 12),
                  _buildTokenRow('Cluster Join Token (Swarm Token)', widget.state.clusterJoinToken, isDark),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleBadge(String title, String desc, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: color)),
          const SizedBox(height: 2),
          Text(desc, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildGroupChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: color),
      ),
    );
  }

  Widget _buildTokenRow(String label, String value, bool isDark) {
    return Row(
      children: [
        SizedBox(
          width: 220,
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value.isNotEmpty ? value : '(Not configured)',
                    style: const TextStyle(fontFamily: 'Courier New', fontSize: 12, color: Color(0xFFF97316)),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 16),
                  tooltip: 'Copy',
                  onPressed: () {
                    ClipboardService.copy(value);
                    _showSnackBar('$label copied to clipboard');
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';

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

class _SecurityPageState extends State<SecurityPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // LDAP State
  List<LDAPConfig> _ldapConfigs = [];
  bool _ldapLoading = true;
  String? _ldapError;

  // Local Users State
  List<LocalUser> _localUsers = [];
  bool _usersLoading = true;
  String? _usersError;

  // Audit Logs State
  List<AuditLog> _auditLogs = [];
  bool _auditLoading = true;
  String? _auditError;
  String _selectedProviderFilter = "";

  // OIDC / SSO State
  List<OIDCConfig> _oidcConfigs = [];
  List<OIDCProviderPreset> _oidcPresets = [];
  bool _oidcLoading = true;
  String? _oidcError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    _loadLDAPConfigs();
    _loadLocalUsers();
    _loadAuditLogs();
    _loadOIDCConfigs();
  }

  Future<void> _loadOIDCConfigs() async {
    setState(() {
      _oidcLoading = true;
      _oidcError = null;
    });
    try {
      final configs = await ApiService.fetchOIDCConfigs();
      final presets = await ApiService.fetchOIDCPresets();
      if (mounted) {
        setState(() {
          _oidcConfigs = configs;
          _oidcPresets = presets;
          _oidcLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _oidcError = e.toString();
          _oidcLoading = false;
        });
      }
    }
  }

  Future<void> _loadLDAPConfigs() async {
    setState(() {
      _ldapLoading = true;
      _ldapError = null;
    });
    try {
      final configs = await ApiService.fetchLDAPConfigs();
      if (mounted) {
        setState(() {
          _ldapConfigs = configs;
          _ldapLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _ldapError = e.toString();
          _ldapLoading = false;
        });
      }
    }
  }

  Future<void> _loadLocalUsers() async {
    setState(() {
      _usersLoading = true;
      _usersError = null;
    });
    try {
      final users = await ApiService.fetchLocalUsers();
      if (mounted) {
        setState(() {
          _localUsers = users;
          _usersLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _usersError = e.toString();
          _usersLoading = false;
        });
      }
    }
  }

  Future<void> _loadAuditLogs() async {
    setState(() {
      _auditLoading = true;
      _auditError = null;
    });
    try {
      final logs = await ApiService.fetchAuditLogs(provider: _selectedProviderFilter);
      if (mounted) {
        setState(() {
          _auditLogs = logs;
          _auditLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _auditError = e.toString();
          _auditLoading = false;
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

  // ---------------------------------------------------------------------------
  // LOCAL USER DIALOGS & ACTIONS
  // ---------------------------------------------------------------------------
  void _openUserDialog([LocalUser? user]) {
    final isEdit = user != null;
    final usernameCtrl = TextEditingController(text: user?.username ?? "");
    final passwordCtrl = TextEditingController();
    final displayNameCtrl = TextEditingController(text: user?.displayName ?? "");
    final emailCtrl = TextEditingController(text: user?.email ?? "");

    String role = user?.role ?? "operator";
    bool enabled = user?.enabled ?? true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                Icon(
                  isEdit ? Icons.manage_accounts : Icons.person_add_alt_1,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Text(isEdit ? "Edit Local User account" : "Create New Local User"),
              ],
            ),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: usernameCtrl,
                      enabled: !isEdit,
                      decoration: const InputDecoration(
                        labelText: "Username *",
                        hintText: "e.g. operator_sec",
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (!isEdit) ...[
                      TextField(
                        controller: passwordCtrl,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: "Password *",
                          hintText: "••••••••",
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: displayNameCtrl,
                      decoration: const InputDecoration(
                        labelText: "Display Name",
                        hintText: "e.g. Security Specialist",
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emailCtrl,
                      decoration: const InputDecoration(
                        labelText: "Email Address",
                        hintText: "user@company.local",
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: role,
                            decoration: const InputDecoration(labelText: "Assigned Role"),
                            items: const [
                              DropdownMenuItem(value: "admin", child: Text("👑 Administrator")),
                              DropdownMenuItem(value: "operator", child: Text("⚡ Operator")),
                              DropdownMenuItem(value: "readonly", child: Text("👁️ Read-Only")),
                            ],
                            onChanged: (v) {
                              if (v != null) setDialogState(() => role = v);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SwitchListTile(
                            title: const Text("Account Active", style: TextStyle(fontSize: 13)),
                            value: enabled,
                            onChanged: (v) => setDialogState(() => enabled = v),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Cancel"),
              ),
              FilledButton(
                onPressed: () async {
                  final username = usernameCtrl.text.trim();
                  if (username.isEmpty) {
                    _showSnackBar("Username is required", isError: true);
                    return;
                  }

                  if (!isEdit) {
                    final pass = passwordCtrl.text;
                    if (pass.isEmpty) {
                      _showSnackBar("Password is required for new users", isError: true);
                      return;
                    }
                    final res = await ApiService.createLocalUser(
                      username: username,
                      password: pass,
                      displayName: displayNameCtrl.text.trim(),
                      email: emailCtrl.text.trim(),
                      role: role,
                      enabled: enabled,
                    );
                    if (res["error"] != null) {
                      _showSnackBar("Failed: " + res["error"].toString(), isError: true);
                      return;
                    }
                    if (mounted) {
                      _showSnackBar("Local user '$username' created successfully");
                    }
                  } else {
                    final updatedUser = LocalUser(
                      id: user.id,
                      username: user.username,
                      displayName: displayNameCtrl.text.trim(),
                      email: emailCtrl.text.trim(),
                      role: role,
                      enabled: enabled,
                      createdAt: user.createdAt,
                      updatedAt: user.updatedAt,
                    );
                    final res = await ApiService.updateLocalUser(updatedUser);
                    if (res["error"] != null) {
                      _showSnackBar("Failed: " + res["error"].toString(), isError: true);
                      return;
                    }
                    if (mounted) {
                      _showSnackBar("User account '${user.username}' updated");
                    }
                  }

                  if (mounted) {
                    Navigator.pop(ctx);
                    _loadLocalUsers();
                  }
                },
                child: Text(isEdit ? "Save Changes" : "Create User"),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openResetPasswordDialog(LocalUser user) {
    final newPassCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.key, color: Colors.orange),
            const SizedBox(width: 10),
            Text("Reset Password - ${user.username}"),
          ],
        ),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: newPassCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: "New Password",
                  hintText: "••••••••",
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmPassCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: "Confirm New Password",
                  hintText: "••••••••",
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () async {
              final newPass = newPassCtrl.text;
              if (newPass.isEmpty) {
                _showSnackBar("New password cannot be empty", isError: true);
                return;
              }
              if (newPass != confirmPassCtrl.text) {
                _showSnackBar("Passwords do not match", isError: true);
                return;
              }
              final res = await ApiService.resetLocalUserPassword(user.id, newPass);
              if (res["error"] != null) {
                _showSnackBar("Failed: " + res["error"].toString(), isError: true);
                return;
              }
              if (mounted) {
                Navigator.pop(ctx);
                _showSnackBar("Password updated successfully for '${user.username}'");
              }
            },
            child: const Text("Reset Password"),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteUser(LocalUser user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Local User"),
        content: Text("Are you sure you want to delete user account '${user.username}'?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final ok = await ApiService.deleteLocalUser(user.id);
      if (ok) {
        if (mounted) {
          _showSnackBar("User account '${user.username}' removed");
          _loadLocalUsers();
        }
      } else {
        if (mounted) {
          _showSnackBar("Failed to remove user account", isError: true);
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // LDAP DIALOG & ACTIONS (Preserved)
  // ---------------------------------------------------------------------------
  void _openLDAPDialog([LDAPConfig? config]) {
    final isEdit = config != null;
    final nameCtrl = TextEditingController(text: config?.name ?? "Corporate Active Directory");
    final hostCtrl = TextEditingController(text: config?.host ?? "");
    final portCtrl = TextEditingController(text: (config?.port ?? 389).toString());
    final baseDnCtrl = TextEditingController(text: config?.baseDn ?? "DC=corp,DC=local");
    final bindDnCtrl = TextEditingController(text: config?.bindDn ?? "");
    final bindPassCtrl = TextEditingController(text: config?.bindPassword ?? "");
    final userFilterCtrl = TextEditingController(text: config?.userFilter ?? "(&(objectClass=user)(sAMAccountName=%s))");
    final userAttrCtrl = TextEditingController(text: config?.userAttr ?? "sAMAccountName");
    final groupBaseDnCtrl = TextEditingController(text: config?.groupBaseDn ?? "");
    final adminGroupCtrl = TextEditingController(text: config?.adminGroupDn ?? "CN=Gubernator_Admins,OU=Groups,DC=corp,DC=local");
    final operatorGroupCtrl = TextEditingController(text: config?.operatorGroupDn ?? "CN=Gubernator_Operators,OU=Groups,DC=corp,DC=local");
    final readOnlyGroupCtrl = TextEditingController(text: config?.readOnlyGroupDn ?? "CN=Gubernator_Viewers,OU=Groups,DC=corp,DC=local");

    String security = config?.security ?? "none";
    bool insecureSkipVerify = config?.insecureSkipVerify ?? false;
    bool enabled = config?.enabled ?? true;
    String defaultRole = config?.defaultRole ?? "readonly";

    bool testing = false;
    LDAPTestResult? testResult;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                Icon(
                  isEdit ? Icons.edit_note : Icons.add_moderator,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Text(isEdit ? "Edit Directory Server" : "Add Active Directory / LDAP Server"),
              ],
            ),
            content: SizedBox(
              width: 680,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: nameCtrl,
                            decoration: const InputDecoration(
                              labelText: "Display Name *",
                              hintText: "e.g. Corporate Active Directory",
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SwitchListTile(
                            title: const Text("Enabled", style: TextStyle(fontSize: 13)),
                            value: enabled,
                            onChanged: (v) => setDialogState(() => enabled = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: hostCtrl,
                            decoration: const InputDecoration(
                              labelText: "LDAP Host / IP *",
                              hintText: "dc1.company.local",
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: portCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: "Port",
                              hintText: "389 / 636",
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: security,
                            decoration: const InputDecoration(labelText: "Security Mode"),
                            items: const [
                              DropdownMenuItem(value: "none", child: Text("None (389)")),
                              DropdownMenuItem(value: "tls", child: Text("LDAPS / TLS (636)")),
                              DropdownMenuItem(value: "starttls", child: Text("StartTLS")),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                setDialogState(() {
                                  security = v;
                                  if (v == "tls" && portCtrl.text == "389") {
                                    portCtrl.text = "636";
                                  } else if (v == "none" && portCtrl.text == "636") {
                                    portCtrl.text = "389";
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
                      title: const Text("Insecure Skip Verify (Accept self-signed domain certificates)", style: TextStyle(fontSize: 12.5)),
                      value: insecureSkipVerify,
                      onChanged: (v) => setDialogState(() => insecureSkipVerify = v ?? false),
                    ),
                    const Divider(height: 24),
                    const Text("Search Credentials (Service Account)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: baseDnCtrl,
                      decoration: const InputDecoration(
                        labelText: "Base DN (Search Base) *",
                        hintText: "DC=company,DC=local",
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: bindDnCtrl,
                            decoration: const InputDecoration(
                              labelText: "Bind DN / Service User",
                              hintText: "CN=svc_gubernator,OU=ServiceAccounts,DC=company,DC=local",
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: bindPassCtrl,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: "Bind Password",
                              hintText: "••••••••",
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    const Text("User Search Filter", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: userFilterCtrl,
                            decoration: const InputDecoration(
                              labelText: "User Filter Query",
                              hintText: "(&(objectClass=user)(sAMAccountName=%s))",
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: userAttrCtrl,
                            decoration: const InputDecoration(
                              labelText: "User Attribute",
                              hintText: "sAMAccountName",
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    const Text("Group to Role Mappings (RBAC)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: groupBaseDnCtrl,
                      decoration: const InputDecoration(
                        labelText: "Group Base DN (Optional)",
                        hintText: "OU=Groups,DC=company,DC=local",
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: adminGroupCtrl,
                      decoration: const InputDecoration(
                        labelText: "Administrator Group DN",
                        hintText: "CN=Gubernator_Admins,OU=Groups,DC=company,DC=local",
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: operatorGroupCtrl,
                      decoration: const InputDecoration(
                        labelText: "Operator Group DN",
                        hintText: "CN=Gubernator_Operators,OU=Groups,DC=company,DC=local",
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: readOnlyGroupCtrl,
                      decoration: const InputDecoration(
                        labelText: "Read-Only Group DN",
                        hintText: "CN=Gubernator_Viewers,OU=Groups,DC=company,DC=local",
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: defaultRole,
                      decoration: const InputDecoration(labelText: "Fallback Default Role (Unmapped Users)"),
                      items: const [
                        DropdownMenuItem(value: "admin", child: Text("👑 Administrator")),
                        DropdownMenuItem(value: "operator", child: Text("⚡ Operator")),
                        DropdownMenuItem(value: "readonly", child: Text("👁️ Read-Only")),
                        DropdownMenuItem(value: "none", child: Text("🚫 Deny Access (No Role)")),
                      ],
                      onChanged: (v) {
                        if (v != null) setDialogState(() => defaultRole = v);
                      },
                    ),

                    if (testing) ...[
                      const SizedBox(height: 16),
                      const LinearProgressIndicator(),
                      const SizedBox(height: 4),
                      const Text("Testing connection to LDAP server...", style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                    ],

                    if (testResult != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: testResult!.connected ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: testResult!.connected ? Colors.green : Colors.red),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  testResult!.connected ? Icons.check_circle : Icons.error,
                                  color: testResult!.connected ? Colors.green : Colors.red,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  testResult!.message,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: testResult!.connected ? Colors.green.shade800 : Colors.red.shade800,
                                  ),
                                ),
                                const Spacer(),
                                Text("${testResult!.latencyMs} ms", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              OutlinedButton.icon(
                icon: const Icon(Icons.bolt, size: 16),
                label: const Text("Test Connection"),
                onPressed: testing
                    ? null
                    : () async {
                        final host = hostCtrl.text.trim();
                        final baseDn = baseDnCtrl.text.trim();
                        if (host.isEmpty || baseDn.isEmpty) {
                          _showSnackBar("Host and Base DN are required for testing", isError: true);
                          return;
                        }
                        setDialogState(() {
                          testing = true;
                          testResult = null;
                        });

                        final cfg = LDAPConfig(
                          id: config?.id ?? "",
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
                child: const Text("Cancel"),
              ),
              FilledButton(
                onPressed: () async {
                  final name = nameCtrl.text.trim();
                  final host = hostCtrl.text.trim();
                  final baseDn = baseDnCtrl.text.trim();

                  if (name.isEmpty || host.isEmpty || baseDn.isEmpty) {
                    _showSnackBar("Please fill all required fields (*)", isError: true);
                    return;
                  }

                  final cfg = LDAPConfig(
                    id: config?.id ?? "",
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
                  if (res["error"] != null) {
                    _showSnackBar("Failed to save directory config: " + res["error"].toString(), isError: true);
                    return;
                  }

                  if (mounted) {
                    Navigator.pop(ctx);
                    _showSnackBar("Directory server configuration saved");
                    _loadLDAPConfigs();
                  }
                },
                child: const Text("Save"),
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
        title: const Text("Delete Directory Server"),
        content: Text("Are you sure you want to remove '${config.name}'? Users from this domain will no longer be able to authenticate."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final ok = await ApiService.deleteLDAPConfig(config.id);
      if (ok) {
        if (mounted) {
          _showSnackBar("Directory server removed");
          _loadLDAPConfigs();
        }
      } else {
        if (mounted) {
          _showSnackBar("Failed to remove directory server", isError: true);
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // UI BUILD METHOD & TABS
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
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
                          "Security, Directory & User Access Control",
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Local user accounts, Active Directory/LDAP servers, RBAC policies, and audit access logs.",
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text("Refresh All"),
                  onPressed: _loadAllData,
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Tab Bar Navigation
            Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.withValues(alpha: 0.2)),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: primaryColor,
                unselectedLabelColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                tabs: const [
                  Tab(icon: Icon(Icons.people_alt_outlined), text: "Local Users"),
                  Tab(icon: Icon(Icons.dns_outlined), text: "Active Directory / LDAP"),
                  Tab(icon: Icon(Icons.vpn_key_outlined), text: "SSO / OIDC"),
                  Tab(icon: Icon(Icons.history_toggle_off), text: "Access & Audit Logs"),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Tab Views Container
            SizedBox(
              height: 720,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildLocalUsersTab(isDark, primaryColor),
                  _buildLDAPTab(isDark, primaryColor),
                  _buildOIDCTab(isDark, primaryColor),
                  _buildAuditLogsTab(isDark, primaryColor),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 1: LOCAL USERS
  // ---------------------------------------------------------------------------
  Widget _buildLocalUsersTab(bool isDark, Color primaryColor) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Configured Local Users",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.person_add, size: 18),
                label: const Text("Add Local User"),
                onPressed: () => _openUserDialog(),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_usersLoading)
            const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
          else if (_usersError != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Text("Error loading local users: " + _usersError!, style: const TextStyle(color: Colors.red)),
            )
          else if (_localUsers.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.withValues(alpha: 0.2)),
              ),
              child: Column(
                children: [
                  Icon(Icons.no_accounts, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  const Text("No local user accounts configured", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  const Text("Create a local account to manage emergency cluster access.", style: TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.withValues(alpha: 0.2)),
              ),
              child: DataTable(
                columns: const [
                  DataColumn(label: Text("Username")),
                  DataColumn(label: Text("Display Name")),
                  DataColumn(label: Text("Email")),
                  DataColumn(label: Text("Role")),
                  DataColumn(label: Text("Status")),
                  DataColumn(label: Text("Last Login")),
                  DataColumn(label: Text("Actions")),
                ],
                rows: _localUsers.map((usr) {
                  return DataRow(
                    cells: [
                      DataCell(Row(
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: primaryColor.withValues(alpha: 0.2),
                            child: Text(usr.username.substring(0, 1).toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: primaryColor)),
                          ),
                          const SizedBox(width: 8),
                          Text(usr.username, style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      )),
                      DataCell(Text(usr.displayName.isEmpty ? "-" : usr.displayName)),
                      DataCell(Text(usr.email.isEmpty ? "-" : usr.email)),
                      DataCell(_buildRoleBadgeLabel(usr.role)),
                      DataCell(
                        Chip(
                          avatar: Icon(usr.enabled ? Icons.check_circle : Icons.block, size: 14, color: usr.enabled ? Colors.green : Colors.red),
                          label: Text(usr.enabled ? "Active" : "Disabled", style: TextStyle(fontSize: 11, color: usr.enabled ? Colors.green.shade800 : Colors.red.shade800)),
                          backgroundColor: (usr.enabled ? Colors.green : Colors.red).withValues(alpha: 0.1),
                          padding: EdgeInsets.zero,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      DataCell(Text(usr.lastLogin != null ? usr.lastLogin!.split("T")[0] : "Never")),
                      DataCell(Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, size: 18),
                            tooltip: "Edit User",
                            onPressed: () => _openUserDialog(usr),
                          ),
                          IconButton(
                            icon: const Icon(Icons.key, size: 18, color: Colors.orange),
                            tooltip: "Reset Password",
                            onPressed: () => _openResetPasswordDialog(usr),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                            tooltip: "Delete User",
                            onPressed: () => _deleteUser(usr),
                          ),
                        ],
                      )),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 2: ACTIVE DIRECTORY / LDAP
  // ---------------------------------------------------------------------------
  Widget _buildLDAPTab(bool isDark, Color primaryColor) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Connected Active Directory / LDAP Servers",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text("Add Directory Server"),
                onPressed: () => _openLDAPDialog(),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_ldapLoading)
            const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
          else if (_ldapError != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Text("Error loading directory servers: " + _ldapError!, style: const TextStyle(color: Colors.red)),
            )
          else if (_ldapConfigs.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.withValues(alpha: 0.2)),
              ),
              child: Column(
                children: [
                  Icon(Icons.dns, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  const Text("No Active Directory / LDAP servers configured", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  const Text("Connect an Active Directory domain or OpenLDAP server to enable SSO and group RBAC.", style: TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _ldapConfigs.length,
              itemBuilder: (ctx, idx) {
                final cfg = _ldapConfigs[idx];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: cfg.enabled ? Colors.green.withValues(alpha: 0.2) : Colors.grey.withValues(alpha: 0.2),
                      child: Icon(Icons.lan, color: cfg.enabled ? Colors.green : Colors.grey),
                    ),
                    title: Text(cfg.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text("${cfg.host}:${cfg.port} | Security: ${cfg.security.toUpperCase()} | Base DN: ${cfg.baseDn}"),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, size: 18),
                          onPressed: () => _openLDAPDialog(cfg),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                          onPressed: () => _deleteLDAP(cfg),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 3: SSO / OIDC PROVIDERS
  // ---------------------------------------------------------------------------
  Widget _buildOIDCTab(bool isDark, Color primaryColor) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "SSO / OIDC Identity Providers",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "OAuth2 / OpenID Connect providers for Single Sign-On authentication.",
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
              FilledButton.icon(
                icon: const Icon(Icons.add_link, size: 18),
                label: const Text("Add SSO Provider"),
                onPressed: () => _openOIDCDialog(),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // OIDC info banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF8B5CF6).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Color(0xFF8B5CF6), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "OIDC/OAuth2 providers appear as SSO buttons on the login page. "
                    "Supported: Keycloak, Google Workspace, Microsoft Azure AD, GitHub, Okta, "
                    "and any generic OpenID Connect 1.0 server. "
                    "Uses PKCE (Proof Key for Code Exchange) for secure authorization.",
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Provider cards / loading / error / empty
          if (_oidcLoading)
            const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
          else if (_oidcError != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Text("Error: $_oidcError", style: const TextStyle(color: Colors.red)),
            )
          else if (_oidcConfigs.isEmpty)
            Container(
              padding: const EdgeInsets.all(40),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                children: [
                  const Icon(Icons.vpn_key_outlined, size: 52, color: Color(0xFF8B5CF6)),
                  const SizedBox(height: 14),
                  const Text(
                    "No SSO providers configured",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "Add a Keycloak, Google, Azure AD, GitHub, or Okta provider\nto enable Single Sign-On on the login screen.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    icon: const Icon(Icons.add_link, size: 18),
                    label: const Text("Add Your First SSO Provider"),
                    onPressed: () => _openOIDCDialog(),
                  ),
                ],
              ),
            )
          else
            ...(_oidcConfigs.map((cfg) => _buildOIDCProviderCard(cfg, isDark, primaryColor))),
        ],
      ),
    );
  }

  Widget _buildOIDCProviderCard(OIDCConfig cfg, bool isDark, Color primaryColor) {
    final meta = _oidcProviderMeta(cfg.providerType, cfg.name);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.withValues(alpha: 0.18),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.12 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Provider icon badge
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: meta.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: meta.color.withValues(alpha: 0.3)),
            ),
            child: Icon(meta.icon, color: meta.color, size: 24),
          ),
          const SizedBox(width: 14),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      cfg.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(width: 8),
                    _oidcBadge(cfg.providerType, meta.color),
                    const SizedBox(width: 8),
                    if (!cfg.enabled)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          "DISABLED",
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  cfg.issuerUrl,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.key, size: 12, color: Colors.grey.shade500),
                    const SizedBox(width: 4),
                    Text(
                      "Client: ${cfg.clientId.length > 20 ? '${cfg.clientId.substring(0, 20)}…' : cfg.clientId}",
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    ),
                    const SizedBox(width: 14),
                    Icon(Icons.manage_accounts, size: 12, color: Colors.grey.shade500),
                    const SizedBox(width: 4),
                    Text(
                      "Default role: ${cfg.defaultRole}",
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Actions
          IconButton(
            icon: const Icon(Icons.wifi_find_outlined, size: 20),
            tooltip: "Test Connection",
            onPressed: () => _testOIDCConfig(cfg),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            tooltip: "Edit",
            onPressed: () => _openOIDCDialog(cfg),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
            tooltip: "Delete",
            onPressed: () => _deleteOIDCConfig(cfg),
          ),
        ],
      ),
    );
  }

  Widget _oidcBadge(String providerType, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        providerType.toUpperCase(),
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  /// Maps provider type to icon + color + label (shared with login screen concept)
  ({IconData icon, Color color}) _oidcProviderMeta(String providerType, String name) {
    switch (providerType) {
      case 'keycloak': return (icon: Icons.lock_open, color: const Color(0xFF00B8D9));
      case 'google':   return (icon: Icons.g_mobiledata, color: const Color(0xFF4285F4));
      case 'github':   return (icon: Icons.code, color: const Color(0xFF6E5494));
      case 'azure':    return (icon: Icons.cloud, color: const Color(0xFF0089D6));
      case 'okta':     return (icon: Icons.shield_outlined, color: const Color(0xFF007DC1));
      default:         return (icon: Icons.vpn_key_outlined, color: const Color(0xFF8B5CF6));
    }
  }

  void _openOIDCDialog([OIDCConfig? existing]) {
    final isEdit = existing != null;
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final issuerCtrl = TextEditingController(text: existing?.issuerUrl ?? '');
    final clientIdCtrl = TextEditingController(text: existing?.clientId ?? '');
    final clientSecretCtrl = TextEditingController(text: existing?.clientSecret ?? '');
    final redirectUriCtrl = TextEditingController(text: existing?.redirectUri ?? '');
    final scopesCtrl = TextEditingController(text: existing?.scopes ?? 'openid profile email');
    final roleClaimCtrl = TextEditingController(text: existing?.roleClaimPath ?? 'groups');
    final adminClaimCtrl = TextEditingController(text: existing?.adminClaim ?? '');
    final operatorClaimCtrl = TextEditingController(text: existing?.operatorClaim ?? '');
    final readonlyClaimCtrl = TextEditingController(text: existing?.readonlyClaim ?? '');

    String providerType = existing?.providerType ?? 'generic';
    String defaultRole = existing?.defaultRole ?? 'readonly';
    bool enabled = existing?.enabled ?? true;
    bool insecureSkipVerify = existing?.insecureSkipVerify ?? false;
    bool isTesting = false;
    OIDCTestResult? testResult;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;

          void applyPreset(OIDCProviderPreset preset) {
            setDialogState(() {
              providerType = preset.type;
              issuerCtrl.text = preset.issuerUrl;
              scopesCtrl.text = preset.scopes;
              roleClaimCtrl.text = preset.roleClaimPath;
              if (nameCtrl.text.isEmpty) nameCtrl.text = preset.name;
            });
          }

          return AlertDialog(
            title: Row(
              children: [
                Icon(
                  isEdit ? Icons.edit_outlined : Icons.add_link,
                  color: const Color(0xFF8B5CF6),
                ),
                const SizedBox(width: 10),
                Text(isEdit ? "Edit SSO / OIDC Provider" : "Add SSO / OIDC Provider"),
              ],
            ),
            content: SizedBox(
              width: 600,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Provider type preset picker
                    if (!isEdit && _oidcPresets.isNotEmpty) ...[
                      const Text(
                        "Quick Start — Select a provider template:",
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _oidcPresets.map((p) {
                          final meta = _oidcProviderMeta(p.type, p.name);
                          final isSelected = providerType == p.type;
                          return InkWell(
                            onTap: () => applyPreset(p),
                            borderRadius: BorderRadius.circular(10),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? meta.color.withValues(alpha: 0.15)
                                    : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC)),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected ? meta.color : Colors.grey.withValues(alpha: 0.25),
                                  width: isSelected ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(meta.icon, color: meta.color, size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    p.name,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: isSelected ? meta.color : null,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const Divider(height: 28),
                    ],

                    // Provider type dropdown (for edit or manual)
                    DropdownButtonFormField<String>(
                      key: ValueKey(providerType),
                      initialValue: providerType,
                      decoration: const InputDecoration(labelText: "Provider Type *"),
                      items: const [
                        DropdownMenuItem(value: 'generic', child: Text("Generic OpenID Connect")),
                        DropdownMenuItem(value: 'keycloak', child: Text("Keycloak")),
                        DropdownMenuItem(value: 'google', child: Text("Google Workspace")),
                        DropdownMenuItem(value: 'github', child: Text("GitHub")),
                        DropdownMenuItem(value: 'azure', child: Text("Microsoft Azure AD")),
                        DropdownMenuItem(value: 'okta', child: Text("Okta")),
                      ],
                      onChanged: (v) => setDialogState(() => providerType = v ?? 'generic'),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: "Display Name *",
                        hintText: "e.g. Corporate Keycloak",
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: issuerCtrl,
                      decoration: const InputDecoration(
                        labelText: "Issuer URL *",
                        hintText: "https://auth.company.com/realms/corporate",
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: clientIdCtrl,
                            decoration: const InputDecoration(
                              labelText: "Client ID *",
                              hintText: "gubernator",
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: clientSecretCtrl,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: "Client Secret",
                              hintText: "Leave blank to keep existing",
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: redirectUriCtrl,
                      decoration: const InputDecoration(
                        labelText: "Redirect URI (optional)",
                        hintText: "Auto-detected if empty — https://gbnt.company.com/api/auth/oidc/callback",
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: scopesCtrl,
                            decoration: const InputDecoration(
                              labelText: "Scopes",
                              hintText: "openid profile email groups",
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: roleClaimCtrl,
                            decoration: const InputDecoration(
                              labelText: "Role Claim Path",
                              hintText: "groups",
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    const Text(
                      "RBAC Group/Claim Mapping",
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Map claim values from the token to Gubernator roles. Leave empty to use the default role.",
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: adminClaimCtrl,
                            decoration: const InputDecoration(
                              labelText: "Admin Claim Value",
                              hintText: "gbnt-admins",
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: operatorClaimCtrl,
                            decoration: const InputDecoration(
                              labelText: "Operator Claim Value",
                              hintText: "gbnt-operators",
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: readonlyClaimCtrl,
                            decoration: const InputDecoration(
                              labelText: "Read-Only Claim Value",
                              hintText: "gbnt-viewers",
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      key: ValueKey(defaultRole),
                      initialValue: defaultRole,
                      decoration: const InputDecoration(labelText: "Default Role"),
                      items: const [
                        DropdownMenuItem(value: 'admin', child: Text("👑 Administrator")),
                        DropdownMenuItem(value: 'operator', child: Text("⚡ Operator")),
                        DropdownMenuItem(value: 'readonly', child: Text("👁️ Read-Only")),
                      ],
                      onChanged: (v) => setDialogState(() => defaultRole = v ?? 'readonly'),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text("Provider Enabled", style: TextStyle(fontSize: 13)),
                            value: enabled,
                            onChanged: (v) => setDialogState(() => enabled = v),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text("Skip TLS Verify", style: TextStyle(fontSize: 13, color: Colors.orange)),
                            value: insecureSkipVerify,
                            onChanged: (v) => setDialogState(() => insecureSkipVerify = v),
                          ),
                        ),
                      ],
                    ),

                    // Test result
                    if (isTesting) ...[
                      const SizedBox(height: 16),
                      const Row(
                        children: [
                          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                          SizedBox(width: 10),
                          Text("Testing OIDC discovery endpoint...", style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                        ],
                      ),
                    ] else if (testResult != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: testResult!.connected
                              ? Colors.green.withValues(alpha: 0.08)
                              : Colors.red.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: testResult!.connected
                                ? Colors.green.withValues(alpha: 0.3)
                                : Colors.red.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  testResult!.connected ? Icons.check_circle : Icons.error_outline,
                                  color: testResult!.connected ? Colors.green : Colors.red,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  testResult!.connected ? "Connection Successful" : "Connection Failed",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: testResult!.connected ? Colors.green : Colors.red,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            _testRow("Issuer Reachable", testResult!.issuerReachable),
                            _testRow("Discovery OK", testResult!.discoveryOk),
                            _testRow("JWKS Reachable", testResult!.jwksReachable),
                            if (testResult!.keyCount > 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  "✓ ${testResult!.keyCount} signing key(s) found",
                                  style: const TextStyle(fontSize: 12, color: Colors.green),
                                ),
                              ),
                            if (testResult!.authorizationEndpoint.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  "Auth: ${testResult!.authorizationEndpoint}",
                                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            if (testResult!.message.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  testResult!.message,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: testResult!.connected ? Colors.green.shade700 : Colors.red.shade700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              // Test connection
              OutlinedButton.icon(
                icon: const Icon(Icons.wifi_find_outlined, size: 16),
                label: const Text("Test Connection"),
                onPressed: isTesting
                    ? null
                    : () async {
                        final cfg = OIDCConfig(
                          id: existing?.id ?? '',
                          name: nameCtrl.text.trim(),
                          providerType: providerType,
                          issuerUrl: issuerCtrl.text.trim(),
                          clientId: clientIdCtrl.text.trim(),
                          clientSecret: clientSecretCtrl.text,
                          redirectUri: redirectUriCtrl.text.trim(),
                          scopes: scopesCtrl.text.trim(),
                          roleClaimPath: roleClaimCtrl.text.trim(),
                          adminClaim: adminClaimCtrl.text.trim(),
                          operatorClaim: operatorClaimCtrl.text.trim(),
                          readonlyClaim: readonlyClaimCtrl.text.trim(),
                          defaultRole: defaultRole,
                          insecureSkipVerify: insecureSkipVerify,
                        );
                        setDialogState(() {
                          isTesting = true;
                          testResult = null;
                        });
                        final res = await ApiService.testOIDCConfig(cfg);
                        setDialogState(() {
                          isTesting = false;
                          testResult = res;
                        });
                      },
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Cancel"),
              ),
              FilledButton(
                onPressed: () async {
                  final name = nameCtrl.text.trim();
                  final issuer = issuerCtrl.text.trim();
                  final clientId = clientIdCtrl.text.trim();
                  if (name.isEmpty || issuer.isEmpty || clientId.isEmpty) {
                    _showSnackBar("Name, Issuer URL, and Client ID are required", isError: true);
                    return;
                  }
                  final cfg = OIDCConfig(
                    id: existing?.id ?? '',
                    name: name,
                    providerType: providerType,
                    enabled: enabled,
                    issuerUrl: issuer,
                    clientId: clientId,
                    clientSecret: clientSecretCtrl.text,
                    redirectUri: redirectUriCtrl.text.trim(),
                    scopes: scopesCtrl.text.trim(),
                    roleClaimPath: roleClaimCtrl.text.trim(),
                    adminClaim: adminClaimCtrl.text.trim(),
                    operatorClaim: operatorClaimCtrl.text.trim(),
                    readonlyClaim: readonlyClaimCtrl.text.trim(),
                    defaultRole: defaultRole,
                    insecureSkipVerify: insecureSkipVerify,
                  );
                  final res = await ApiService.saveOIDCConfig(cfg);
                  if (res['error'] != null) {
                    if (mounted) _showSnackBar("Failed: ${res['error']}", isError: true);
                    return;
                  }
                  if (mounted) {
                    Navigator.pop(ctx);
                    _showSnackBar(isEdit
                        ? "SSO provider '${cfg.name}' updated successfully"
                        : "SSO provider '${cfg.name}' added — it will appear on the login screen");
                    _loadOIDCConfigs();
                  }
                },
                child: Text(isEdit ? "Save Changes" : "Add Provider"),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _testRow(String label, bool ok) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          Icon(ok ? Icons.check : Icons.close, size: 14, color: ok ? Colors.green : Colors.red),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Future<void> _testOIDCConfig(OIDCConfig cfg) async {
    _showSnackBar("Testing connection to ${cfg.name}...");
    final result = await ApiService.testOIDCConfig(cfg);
    if (!mounted) return;
    final msg = result.connected
        ? "✓ ${cfg.name} — OIDC discovery OK (${result.keyCount} signing keys, ${result.latencyMs}ms)"
        : "✗ ${cfg.name} — ${result.message}";
    _showSnackBar(msg, isError: !result.connected);
  }

  Future<void> _deleteOIDCConfig(OIDCConfig cfg) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Remove SSO Provider"),
        content: Text(
          "Remove '${cfg.name}'?\n\nThe SSO button will disappear from the login screen immediately.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Remove"),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final ok = await ApiService.deleteOIDCConfig(cfg.id);
      if (ok) {
        if (mounted) {
          _showSnackBar("SSO provider '${cfg.name}' removed");
          _loadOIDCConfigs();
        }
      } else {
        if (mounted) _showSnackBar("Failed to remove provider", isError: true);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // TAB 4: ACCESS & AUDIT LOGS
  // ---------------------------------------------------------------------------
  Widget _buildAuditLogsTab(bool isDark, Color primaryColor) {

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Access & Security Audit Trail",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  DropdownButton<String>(
                    value: _selectedProviderFilter,
                    items: const [
                      DropdownMenuItem(value: "", child: Text("All Providers")),
                      DropdownMenuItem(value: "LOCAL", child: Text("LOCAL Provider")),
                      DropdownMenuItem(value: "ACTIVE_DIRECTORY", child: Text("ACTIVE DIRECTORY")),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _selectedProviderFilter = v);
                        _loadAuditLogs();
                      }
                    },
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _loadAuditLogs,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_auditLoading)
            const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
          else if (_auditError != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Text("Error loading audit logs: " + _auditError!, style: const TextStyle(color: Colors.red)),
            )
          else if (_auditLogs.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.withValues(alpha: 0.2)),
              ),
              child: Column(
                children: [
                  Icon(Icons.assignment_outlined, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  const Text("No audit records found", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  const Text("Security events and login attempts will be logged automatically here.", style: TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.withValues(alpha: 0.2)),
              ),
              child: DataTable(
                columns: const [
                  DataColumn(label: Text("Timestamp")),
                  DataColumn(label: Text("User")),
                  DataColumn(label: Text("Provider")),
                  DataColumn(label: Text("Action")),
                  DataColumn(label: Text("Status")),
                  DataColumn(label: Text("IP Address")),
                  DataColumn(label: Text("Details")),
                ],
                rows: _auditLogs.map((log) {
                  final isSuccess = log.status.toUpperCase() == "SUCCESS";
                  return DataRow(
                    cells: [
                      DataCell(Text(log.timestamp.replaceAll("T", " ").split(".")[0], style: const TextStyle(fontSize: 12))),
                      DataCell(Text(log.username, style: const TextStyle(fontWeight: FontWeight.bold))),
                      DataCell(Chip(
                        label: Text(log.provider, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                        backgroundColor: (log.provider == "LOCAL" ? Colors.blue : Colors.purple).withValues(alpha: 0.15),
                        padding: EdgeInsets.zero,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      )),
                      DataCell(Text(log.action, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
                      DataCell(Chip(
                        avatar: Icon(isSuccess ? Icons.check_circle : Icons.cancel, size: 12, color: isSuccess ? Colors.green : Colors.red),
                        label: Text(log.status, style: TextStyle(fontSize: 10, color: isSuccess ? Colors.green.shade900 : Colors.red.shade900)),
                        backgroundColor: (isSuccess ? Colors.green : Colors.red).withValues(alpha: 0.15),
                        padding: EdgeInsets.zero,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      )),
                      DataCell(Text(log.ipAddress.isEmpty ? "-" : log.ipAddress, style: const TextStyle(fontSize: 12))),
                      DataCell(Text(log.details, style: const TextStyle(fontSize: 12))),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------------
  Widget _buildRoleBadgeLabel(String role) {
    switch (role.toLowerCase()) {
      case "admin":
        return const Chip(
          avatar: Text("👑", style: TextStyle(fontSize: 10)),
          label: Text("Administrator", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber)),
          backgroundColor: Color(0x33FFC107),
          padding: EdgeInsets.zero,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        );
      case "operator":
        return const Chip(
          avatar: Text("⚡", style: TextStyle(fontSize: 10)),
          label: Text("Operator", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue)),
          backgroundColor: Color(0x332196F3),
          padding: EdgeInsets.zero,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        );
      default:
        return const Chip(
          avatar: Text("👁️", style: TextStyle(fontSize: 10)),
          label: Text("Read-Only", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green)),
          backgroundColor: Color(0x334CAF50),
          padding: EdgeInsets.zero,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        );
    }
  }
}

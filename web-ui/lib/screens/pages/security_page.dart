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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
  // TAB 3: ACCESS & AUDIT LOGS
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

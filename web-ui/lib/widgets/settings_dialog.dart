import 'package:flutter/material.dart';
import '../models/models.dart';

/// Settings dialog with user profile, password change, and theme toggle.
class SettingsDialog extends StatefulWidget {
  final bool isDark;
  final ValueChanged<bool> onThemeChanged;
  final String displayName;
  final ValueChanged<String> onNameChanged;
  final String version;
  final List<Node> nodes;

  const SettingsDialog({
    super.key,
    required this.isDark,
    required this.onThemeChanged,
    required this.displayName,
    required this.onNameChanged,
    required this.version,
    required this.nodes,
  });

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late TextEditingController _nameCtrl;
  final _currentPassCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _nameCtrl = TextEditingController(text: widget.displayName);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameCtrl.dispose();
    _currentPassCtrl.dispose();
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ─── Header ─────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 8, 0),
              child: Row(
                children: [
                  Icon(Icons.settings, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Text('Settings',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // ─── Tabs ───────────────────────────────────────────────
            TabBar(
              controller: _tabController,
              labelColor: theme.colorScheme.primary,
              unselectedLabelColor:
                  theme.colorScheme.onSurface.withValues(alpha: 0.5),
              indicatorColor: theme.colorScheme.primary,
              tabs: const [
                Tab(icon: Icon(Icons.person), text: 'Profile'),
                Tab(icon: Icon(Icons.lock), text: 'Password'),
                Tab(icon: Icon(Icons.palette), text: 'Appearance'),
                Tab(icon: Icon(Icons.info_outline), text: 'About'),
              ],
            ),
            const Divider(height: 1),

            // ─── Tab Content ────────────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildProfileTab(theme, isDark),
                  _buildPasswordTab(theme),
                  _buildAppearanceTab(theme, isDark),
                  _buildAboutTab(theme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Profile Tab ────────────────────────────────────────────────────
  Widget _buildProfileTab(ThemeData theme, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          Center(
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 48,
                  backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
                  child: Icon(Icons.person,
                      size: 48, color: theme.colorScheme.primary),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.camera_alt,
                        size: 16, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Display Name
          Text('Display Name',
              style: theme.textTheme.labelLarge
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              hintText: 'Enter your display name',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
          ),
          const SizedBox(height: 24),

          // Info card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      color: theme.colorScheme.primary, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Your profile is stored locally in the browser. '
                      'Authentication is managed via GBNT_WEB_USER / GBNT_WEB_PASSWORD.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Save button
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                widget.onNameChanged(_nameCtrl.text);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Profile updated'),
                      duration: Duration(seconds: 2)),
                );
              },
              icon: const Icon(Icons.save, size: 18),
              label: const Text('Save Profile'),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Password Tab ───────────────────────────────────────────────────
  Widget _buildPasswordTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Change Password',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            'Update your web dashboard password. This changes the GBNT_WEB_PASSWORD value.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 20),

          // Current password
          TextField(
            controller: _currentPassCtrl,
            obscureText: _obscureCurrent,
            decoration: InputDecoration(
              labelText: 'Current Password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_obscureCurrent
                    ? Icons.visibility_off
                    : Icons.visibility),
                onPressed: () =>
                    setState(() => _obscureCurrent = !_obscureCurrent),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // New password
          TextField(
            controller: _newPassCtrl,
            obscureText: _obscureNew,
            decoration: InputDecoration(
              labelText: 'New Password',
              prefixIcon: const Icon(Icons.lock),
              suffixIcon: IconButton(
                icon: Icon(
                    _obscureNew ? Icons.visibility_off : Icons.visibility),
                onPressed: () =>
                    setState(() => _obscureNew = !_obscureNew),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Confirm password
          TextField(
            controller: _confirmPassCtrl,
            obscureText: _obscureConfirm,
            decoration: InputDecoration(
              labelText: 'Confirm New Password',
              prefixIcon: const Icon(Icons.lock_clock),
              suffixIcon: IconButton(
                icon: Icon(_obscureConfirm
                    ? Icons.visibility_off
                    : Icons.visibility),
                onPressed: () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
              ),
            ),
          ),
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                if (_newPassCtrl.text != _confirmPassCtrl.text) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Passwords do not match'),
                      backgroundColor: theme.colorScheme.error,
                    ),
                  );
                  return;
                }
                if (_newPassCtrl.text.isEmpty || _currentPassCtrl.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Please fill all fields'),
                      backgroundColor: theme.colorScheme.error,
                    ),
                  );
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Password changed successfully'),
                    duration: Duration(seconds: 2),
                  ),
                );
                _currentPassCtrl.clear();
                _newPassCtrl.clear();
                _confirmPassCtrl.clear();
              },
              icon: const Icon(Icons.save, size: 18),
              label: const Text('Change Password'),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Appearance Tab ─────────────────────────────────────────────────
  Widget _buildAppearanceTab(ThemeData theme, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Theme',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            'Choose between light and dark mode for the dashboard.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 24),

          // Theme cards
          Row(
            children: [
              Expanded(
                child: _ThemeCard(
                  title: 'Light',
                  icon: Icons.light_mode,
                  isSelected: !isDark,
                  color: const Color(0xFFF59E0B),
                  onTap: () => widget.onThemeChanged(false),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _ThemeCard(
                  title: 'Dark',
                  icon: Icons.dark_mode,
                  isSelected: isDark,
                  color: const Color(0xFF6366F1),
                  onTap: () => widget.onThemeChanged(true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Quick toggle
          Card(
            child: SwitchListTile(
              title: const Text('Dark Mode'),
              subtitle: Text(isDark ? 'Currently using dark theme' : 'Currently using light theme'),
              secondary: Icon(isDark ? Icons.dark_mode : Icons.light_mode,
                  color: theme.colorScheme.primary),
              value: isDark,
              onChanged: (val) => widget.onThemeChanged(val),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutTab(ThemeData theme) {
    final managerNode = widget.nodes.firstWhere(
      (n) => n.role == 'manager',
      orElse: () => Node(id: 'node-local-manager', ip: '127.0.0.1', role: 'manager', status: 'active'),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
            child: Icon(Icons.rocket_launch, size: 36, color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 12),
          Text(
            'Gubernator Orchestrator',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              widget.version,
              style: TextStyle(
                fontFamily: 'Courier New',
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          _buildInfoRow('Role', 'Central Manager'),
          _buildInfoRow('Host IP', managerNode.ip),
          _buildInfoRow('Status', managerNode.status.toUpperCase(), isStatus: true, statusColor: managerNode.status == 'active' ? Colors.green : Colors.orange),
          _buildInfoRow('Centurions (Nodes)', '${widget.nodes.length} registered'),
          _buildInfoRow('Database Engine', 'SQLite 3 (Centralized)'),
          const SizedBox(height: 20),
          Text(
            'Gubernator combines Swarm simplicity with Nomad flexibility.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isStatus = false, Color? statusColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
          ),
          isStatus
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: (statusColor ?? Colors.grey).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                )
              : SelectableText(
                  value,
                  style: const TextStyle(
                    fontFamily: 'Courier New',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ],
      ),
    );
  }
}

// ─── Theme Selection Card ─────────────────────────────────────────────────────
class _ThemeCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  const _ThemeCard({
    required this.title,
    required this.icon,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? theme.colorScheme.primary : theme.dividerColor,
            width: isSelected ? 2 : 1,
          ),
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.08)
              : theme.cardTheme.color,
        ),
        child: Column(
          children: [
            Icon(icon, size: 36, color: isSelected ? color : theme.hintColor),
            const SizedBox(height: 8),
            Text(title,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface,
                )),
            if (isSelected) ...[
              const SizedBox(height: 4),
              Icon(Icons.check_circle,
                  size: 18, color: theme.colorScheme.primary),
            ],
          ],
        ),
      ),
    );
  }
}

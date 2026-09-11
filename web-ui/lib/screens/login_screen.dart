import 'dart:html' as html;
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';

class LoginScreen extends StatefulWidget {
  final ValueChanged<UserSession> onLoginSuccess;

  const LoginScreen({super.key, required this.onLoginSuccess});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;
  bool _oidcLoading = false;
  String? _errorMessage;

  // MFA Challenge State (ENS op.acc.2)
  bool _mfaRequired = false;
  String? _mfaToken;
  String? _mfaUsername;
  final _mfaCodeController = TextEditingController();
  bool _mfaLoading = false;

  // Providers: local + ldap (for form login)
  List<AuthProvider> _formProviders = [
    const AuthProvider(id: 'local', name: 'Local Administrator', type: 'local'),
  ];
  // OIDC providers (SSO buttons)
  List<OIDCConfig> _oidcProviders = [];

  String _selectedProvider = 'local';
  bool _loadingProviders = true;

  @override
  void initState() {
    super.initState();
    _loadProviders();
    _checkOIDCCallback();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _mfaCodeController.dispose();
    super.dispose();
  }

  // ── Check if we're returning from an OIDC callback ──────────────────────
  void _checkOIDCCallback() {
    final uri = Uri.base;
    // Handle successful OIDC callback with token
    final token = uri.queryParameters['oidc_token'];
    if (token != null && token.isNotEmpty) {
      ApiService.authToken = token;
      ApiService.fetchMe().then((user) {
        if (mounted) {
          html.window.history.replaceState(null, '', '/#/');
          if (user != null) {
            widget.onLoginSuccess(user);
          } else {
            setState(() => _errorMessage = 'SSO authentication failed — could not load user session');
          }
        }
      }).catchError((e) {
        if (mounted) {
          setState(() => _errorMessage = 'SSO session error: $e');
        }
      });
    }
    // Handle OIDC error redirect from the IdP
    final oidcError = uri.queryParameters['oidc_error'];
    if (oidcError != null && oidcError.isNotEmpty) {
      html.window.history.replaceState(null, '', '/#/');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _errorMessage = 'SSO Error: $oidcError');
      });
    }
  }

  // ── Load all providers ───────────────────────────────────────────────────
  Future<void> _loadProviders() async {
    try {
      final allProviders = await ApiService.fetchAuthProviders();
      final oidcConfigs = await ApiService.fetchOIDCConfigs();

      if (mounted) {
        setState(() {
          _formProviders = allProviders.where((p) => !p.isOIDC).toList();
          if (_formProviders.isEmpty) {
            _formProviders = [
              const AuthProvider(id: 'local', name: 'Local Administrator', type: 'local'),
            ];
          }
          _oidcProviders = oidcConfigs.where((o) => o.enabled).toList();
          if (!_formProviders.any((p) => p.id == _selectedProvider)) {
            _selectedProvider = _formProviders.first.id;
          }
          _loadingProviders = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingProviders = false);
    }
  }

  // ── Standard form login ──────────────────────────────────────────────────
  Future<void> _handleLogin() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Please enter both username and password');
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    final res = await ApiService.login(username, password, provider: _selectedProvider);

    if (!mounted) return;

    if (res['success'] == true) {
      if (res['mfa_required'] == true) {
        setState(() {
          _loading = false;
          _mfaRequired = true;
          _mfaToken = res['mfa_token'];
          _mfaUsername = res['username'] ?? username;
          _errorMessage = null;
        });
        return;
      }
      if (res['user'] != null) {
        widget.onLoginSuccess(res['user'] as UserSession);
        return;
      }
    }

    setState(() {
      _loading = false;
      _errorMessage = res['error'] ?? 'Authentication failed';
    });
  }

  // ── MFA Verification (ENS op.acc.2) ──────────────────────────────────────
  Future<void> _handleMFAVerify() async {
    final code = _mfaCodeController.text.trim();
    if (code.isEmpty) {
      setState(() => _errorMessage = 'Please enter the 6-digit TOTP or backup recovery code');
      return;
    }

    setState(() {
      _mfaLoading = true;
      _errorMessage = null;
    });

    final res = await ApiService.verifyMFA(
      mfaToken: _mfaToken ?? '',
      code: code,
    );

    if (!mounted) return;

    if (res['success'] == true && res['user'] != null) {
      widget.onLoginSuccess(res['user'] as UserSession);
    } else {
      setState(() {
        _mfaLoading = false;
        _errorMessage = res['error'] ?? 'Invalid or expired MFA code';
      });
    }
  }

  void _cancelMFA() {
    setState(() {
      _mfaRequired = false;
      _mfaToken = null;
      _mfaUsername = null;
      _mfaCodeController.clear();
      _mfaLoading = false;
      _errorMessage = null;
    });
  }

  // ── OIDC / SSO login ─────────────────────────────────────────────────────
  Future<void> _handleOIDCLogin(OIDCConfig provider) async {
    setState(() {
      _oidcLoading = true;
      _errorMessage = null;
    });

    final result = await ApiService.getOIDCAuthorizeUrl(provider.id);

    if (!mounted) return;

    if (result['auth_url'] != null) {
      // Open the OIDC authorization URL in the same tab
      html.window.location.href = result['auth_url'] as String;
    } else {
      setState(() {
        _oidcLoading = false;
        _errorMessage = result['error'] ?? 'Failed to start SSO login';
      });
    }
  }

  // ── Provider icon / color helpers ────────────────────────────────────────
  IconData _providerIcon(String type) {
    switch (type) {
      case 'ldap': return Icons.security;
      case 'oidc': return Icons.vpn_key_outlined;
      default: return Icons.admin_panel_settings;
    }
  }

  Color _providerColor(String type) {
    switch (type) {
      case 'ldap': return const Color(0xFF38BDF8);
      case 'oidc': return const Color(0xFF8B5CF6);
      default: return const Color(0xFFF59E0B);
    }
  }

  /// Icon + color for specific OIDC provider type
  ({IconData icon, Color color, String label}) _oidcProviderMeta(String providerType, String name) {
    switch (providerType) {
      case 'keycloak':
        return (icon: Icons.lock_open, color: const Color(0xFF00B8D9), label: name.isEmpty ? 'Keycloak' : name);
      case 'google':
        return (icon: Icons.g_mobiledata, color: const Color(0xFF4285F4), label: name.isEmpty ? 'Google' : name);
      case 'github':
        return (icon: Icons.code, color: const Color(0xFF6E5494), label: name.isEmpty ? 'GitHub' : name);
      case 'azure':
        return (icon: Icons.cloud, color: const Color(0xFF0089D6), label: name.isEmpty ? 'Microsoft Azure AD' : name);
      case 'okta':
        return (icon: Icons.shield_outlined, color: const Color(0xFF007DC1), label: name.isEmpty ? 'Okta' : name);
      default:
        return (icon: Icons.vpn_key_outlined, color: const Color(0xFF8B5CF6), label: name.isEmpty ? 'SSO' : name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final hasOIDC = _oidcProviders.isNotEmpty;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [const Color(0xFF0F172A), const Color(0xFF1E1B4B), const Color(0xFF0F172A)]
                : [const Color(0xFFF8FAFC), const Color(0xFFE2E8F0), const Color(0xFFEEF2F6)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              width: 460,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B).withValues(alpha: 0.95) : Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.1),
                    blurRadius: 30,
                    offset: const Offset(0, 15),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Logo ─────────────────────────────────────────────
                  Center(
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [primaryColor, const Color(0xFFD97706)],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: primaryColor.withValues(alpha: 0.4),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Text('🏛', style: TextStyle(fontSize: 32)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'GUBERNATOR',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Trajan Pro',
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Enterprise Cluster Orchestration',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      letterSpacing: 0.5,
                    ),
                  ),

                  // ── MFA View or Standard Login Form ──────────────────
                  if (_mfaRequired)
                    _buildMFAView(context, isDark)
                  else ...[
                    // ── OIDC SSO Buttons ─────────────────────────────────
                    if (hasOIDC || _loadingProviders) ...[
                      const SizedBox(height: 28),
                      _buildSectionLabel(context, 'Single Sign-On', Icons.vpn_key_outlined, const Color(0xFF8B5CF6)),
                      const SizedBox(height: 10),
                      if (_loadingProviders)
                        const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                      else
                        ...(_oidcProviders.map((p) {
                          final meta = _oidcProviderMeta(p.providerType, p.name);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _OIDCSSOButton(
                              icon: meta.icon,
                              color: meta.color,
                              label: 'Continue with ${meta.label}',
                              loading: _oidcLoading,
                              onPressed: () => _handleOIDCLogin(p),
                            ),
                          );
                        })),
                      const SizedBox(height: 20),
                      _buildDivider(context, isDark),
                      const SizedBox(height: 20),
                    ] else
                      const SizedBox(height: 28),

                    // ── Form-based login (Local / LDAP) ───────────────────
                    _buildSectionLabel(context, 'Directory Authentication', Icons.corporate_fare, const Color(0xFF38BDF8)),
                    const SizedBox(height: 10),

                    // Provider selector
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.withValues(alpha: 0.25)),
                      ),
                      child: _loadingProviders
                          ? const SizedBox(
                              height: 48,
                              child: Center(
                                child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                              ),
                            )
                          : DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedProvider,
                                isExpanded: true,
                                icon: const Icon(Icons.unfold_more, size: 18),
                                items: _formProviders.map((p) {
                                  return DropdownMenuItem<String>(
                                    value: p.id,
                                    child: Row(
                                      children: [
                                        Icon(
                                          _providerIcon(p.type),
                                          size: 18,
                                          color: _providerColor(p.type),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            p.name,
                                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) setState(() => _selectedProvider = val);
                                },
                              ),
                            ),
                    ),
                    const SizedBox(height: 16),

                    // Username
                    Text(
                      'Username / sAMAccountName',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _usernameController,
                      decoration: InputDecoration(
                        hintText: _selectedProvider == 'local' ? 'admin' : 'user@company.local',
                        prefixIcon: const Icon(Icons.person_outline, size: 20),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.25)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.25)),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      onSubmitted: (_) => _handleLogin(),
                    ),
                    const SizedBox(height: 14),

                    // Password
                    Text(
                      'Password',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        hintText: '••••••••',
                        prefixIcon: const Icon(Icons.lock_outline, size: 20),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                            size: 20,
                          ),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.25)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.25)),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      onSubmitted: (_) => _handleLogin(),
                    ),
                    const SizedBox(height: 16),

                    // Error banner
                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: Colors.red, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(color: Colors.red, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // Sign In button
                    FilledButton(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _loading ? null : _handleLogin,
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Sign In', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 12),

                    // Quick Admin shortcut
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.flash_on, size: 16, color: Color(0xFFF59E0B)),
                      label: const Text('Quick Local Admin (admin / admin)', style: TextStyle(fontSize: 12)),
                      onPressed: () {
                        setState(() {
                          _selectedProvider = 'local';
                          _usernameController.text = 'admin';
                          _passwordController.text = 'admin';
                        });
                        _handleLogin();
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMFAView(BuildContext context, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF0EA5E9).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF0EA5E9).withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.shield, color: Color(0xFF0EA5E9), size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Multi-Factor Authentication (MFA)',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0EA5E9)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'ENS op.acc.2 • TOTP RFC 6238',
                      style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Enter the 6-digit verification code from your Authenticator app (Google Authenticator, Microsoft Authenticator, etc.) or a one-time backup recovery code for user "${_mfaUsername ?? ''}".',
          style: TextStyle(fontSize: 12, height: 1.4, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75)),
        ),
        const SizedBox(height: 18),
        Text(
          'Security Code / Recovery Code',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _mfaCodeController,
          autofocus: true,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 22,
            letterSpacing: 6,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
          decoration: InputDecoration(
            hintText: '000000',
            hintStyle: TextStyle(
              letterSpacing: 6,
              color: Colors.grey.withValues(alpha: 0.4),
            ),
            prefixIcon: const Icon(Icons.phonelink_lock, size: 22),
            filled: true,
            fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.25)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.25)),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
          onSubmitted: (_) => _handleMFAVerify(),
        ),
        const SizedBox(height: 16),
        if (_errorMessage != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        FilledButton.icon(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          icon: _mfaLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.verified_user, size: 18),
          label: Text(
            _mfaLoading ? 'Verifying...' : 'Verify Code & Sign In',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          onPressed: _mfaLoading ? null : _handleMFAVerify,
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          icon: const Icon(Icons.arrow_back, size: 16),
          label: const Text('Back to Login', style: TextStyle(fontSize: 12)),
          onPressed: _cancelMFA,
        ),
      ],
    );
  }

  Widget _buildSectionLabel(BuildContext context, String label, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }

  Widget _buildDivider(BuildContext context, bool isDark) {
    return Row(
      children: [
        Expanded(child: Divider(color: Colors.grey.withValues(alpha: isDark ? 0.2 : 0.3))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'OR',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
              letterSpacing: 1,
            ),
          ),
        ),
        Expanded(child: Divider(color: Colors.grey.withValues(alpha: isDark ? 0.2 : 0.3))),
      ],
    );
  }
}

// ── OIDC SSO Button widget ──────────────────────────────────────────────────
class _OIDCSSOButton extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String label;
  final bool loading;
  final VoidCallback onPressed;

  const _OIDCSSOButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  @override
  State<_OIDCSSOButton> createState() => _OIDCSSOButtonState();
}

class _OIDCSSOButtonState extends State<_OIDCSSOButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: _hovered
              ? widget.color.withValues(alpha: 0.12)
              : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC)),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _hovered ? widget.color.withValues(alpha: 0.5) : Colors.grey.withValues(alpha: 0.25),
            width: _hovered ? 1.5 : 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: widget.loading ? null : widget.onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.loading)
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: widget.color),
                    )
                  else
                    Icon(widget.icon, size: 20, color: widget.color),
                  const SizedBox(width: 10),
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _hovered
                          ? widget.color
                          : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

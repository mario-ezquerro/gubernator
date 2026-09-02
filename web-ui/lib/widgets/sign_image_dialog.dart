import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/models.dart';
import '../services/api_service.dart';

/// Interactive dialog for signing container images using in-cluster ECDSA keypairs or manual keys.
class SignImageDialog extends StatefulWidget {
  final String? initialImage;
  final List<String> availableImages;
  final List<TrustedKeyModel> availableKeys;
  final VoidCallback? onSigned;

  const SignImageDialog({
    super.key,
    this.initialImage,
    this.availableImages = const [],
    this.availableKeys = const [],
    this.onSigned,
  });

  @override
  State<SignImageDialog> createState() => _SignImageDialogState();
}

class _SignImageDialogState extends State<SignImageDialog> {
  late TextEditingController _imageCtrl;
  late TextEditingController _signerCtrl;
  final TextEditingController _customPrivKeyCtrl = TextEditingController();

  String _selectedImageOption = '';
  String _selectedKeyId = '';
  bool _useCustomKey = false;
  bool _signing = false;
  String? _errorMessage;
  Map<String, dynamic>? _signResult;

  @override
  void initState() {
    super.initState();
    final initImg = widget.initialImage ?? (widget.availableImages.isNotEmpty ? widget.availableImages.first : '');
    _imageCtrl = TextEditingController(text: initImg);
    _selectedImageOption = widget.availableImages.contains(initImg) ? initImg : 'custom';

    // Default to the first default key with private key, or first available key
    if (widget.availableKeys.isNotEmpty) {
      final defaultKey = widget.availableKeys.firstWhere(
        (k) => k.isDefault && k.hasPrivateKey,
        orElse: () => widget.availableKeys.firstWhere(
          (k) => k.hasPrivateKey,
          orElse: () => widget.availableKeys.first,
        ),
      );
      _selectedKeyId = defaultKey.id;
      _signerCtrl = TextEditingController(text: defaultKey.name);
      _useCustomKey = !defaultKey.hasPrivateKey;
    } else {
      _selectedKeyId = 'custom';
      _useCustomKey = true;
      _signerCtrl = TextEditingController(text: 'Cluster Administrator');
    }
  }

  @override
  void dispose() {
    _imageCtrl.dispose();
    _signerCtrl.dispose();
    _customPrivKeyCtrl.dispose();
    super.dispose();
  }

  TrustedKeyModel? get _currentSelectedKey {
    try {
      return widget.availableKeys.firstWhere((k) => k.id == _selectedKeyId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _executeSigning() async {
    final imageToSign = _selectedImageOption == 'custom' ? _imageCtrl.text.trim() : _selectedImageOption;
    if (imageToSign.isEmpty) {
      setState(() => _errorMessage = 'Please select or enter an image to sign');
      return;
    }

    final key = _currentSelectedKey;
    String? privKey;
    String? keyId;

    if (_useCustomKey || key == null || !key.hasPrivateKey) {
      privKey = _customPrivKeyCtrl.text.trim();
      if (privKey.isEmpty) {
        setState(() => _errorMessage = 'Private key (PEM format) is required for custom/external signing');
        return;
      }
    } else {
      keyId = key.id;
    }

    setState(() {
      _signing = true;
      _errorMessage = null;
    });

    try {
      final res = await ApiService.signImage(
        imageToSign,
        keyId: keyId,
        privateKey: privKey,
        signerName: _signerCtrl.text.trim().isEmpty ? 'Cluster Administrator' : _signerCtrl.text.trim(),
      );

      if (mounted) {
        setState(() {
          _signing = false;
          _signResult = res;
        });
        if (widget.onSigned != null) {
          widget.onSigned!();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _signing = false;
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 680,
        constraints: const BoxConstraints(maxHeight: 780),
        padding: const EdgeInsets.all(24.0),
        child: _signResult != null ? _buildSuccessView(isDark) : _buildSigningForm(isDark),
      ),
    );
  }

  Widget _buildSigningForm(bool isDark) {
    final key = _currentSelectedKey;
    final hasStoredPrivKey = key != null && key.hasPrivateKey && !_useCustomKey;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title Header
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.verified_user, color: Color(0xFF10B981), size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Cryptographically Sign Image',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Apply The Imperial Seal with ECDSA P-256 keys to pass Gatekeeper admission policies.',
                    style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.black54),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const Divider(height: 1),
        const SizedBox(height: 16),

        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // ── 1. Image Selection ─────────────────────────────────────────
                const Text(
                  '1. Target Container Image',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
                const SizedBox(height: 8),

                if (widget.availableImages.isNotEmpty) ...[
                  DropdownButtonFormField<String>(
                    value: _selectedImageOption,
                    isExpanded: true,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.layers, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    items: [
                      for (final img in widget.availableImages)
                        DropdownMenuItem(
                          value: img,
                          child: Text(
                            img,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      const DropdownMenuItem(
                        value: 'custom',
                        child: Text(
                          '✏️ Custom image name / tag...',
                          style: TextStyle(fontStyle: FontStyle.italic, color: Colors.blueAccent),
                        ),
                      ),
                    ],
                    onChanged: _signing
                        ? null
                        : (val) {
                            if (val != null) {
                              setState(() {
                                _selectedImageOption = val;
                                if (val != 'custom') {
                                  _imageCtrl.text = val;
                                }
                              });
                            }
                          },
                  ),
                  const SizedBox(height: 8),
                ],

                if (_selectedImageOption == 'custom' || widget.availableImages.isEmpty) ...[
                  TextField(
                    controller: _imageCtrl,
                    enabled: !_signing,
                    decoration: InputDecoration(
                      labelText: 'Image Repository & Tag',
                      hintText: 'e.g. registry.company.com/app:v1.2.0 or redis:7-alpine',
                      prefixIcon: const Icon(Icons.image, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // ── 2. Signing Key Selection ──────────────────────────────────
                const Text(
                  '2. In-Cluster Signing Keypair',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
                const SizedBox(height: 8),

                if (widget.availableKeys.isNotEmpty) ...[
                  DropdownButtonFormField<String>(
                    value: _useCustomKey ? 'custom' : _selectedKeyId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.vpn_key_outlined, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    items: [
                      for (final k in widget.availableKeys)
                        DropdownMenuItem(
                          value: k.id,
                          child: Row(
                            children: [
                              Icon(
                                k.hasPrivateKey ? Icons.lock : Icons.lock_open,
                                size: 16,
                                color: k.hasPrivateKey ? const Color(0xFF10B981) : Colors.orangeAccent,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  k.name,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (k.isDefault) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text('DEFAULT', style: TextStyle(fontSize: 10, color: Colors.amber, fontWeight: FontWeight.bold)),
                                ),
                              ],
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: k.hasPrivateKey ? const Color(0xFF10B981).withOpacity(0.15) : Colors.grey.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  k.hasPrivateKey ? 'READY TO SIGN' : 'PUBLIC ONLY',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: k.hasPrivateKey ? const Color(0xFF10B981) : Colors.grey,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const DropdownMenuItem(
                        value: 'custom',
                        child: Row(
                          children: [
                            Icon(Icons.edit_note, size: 16, color: Colors.blueAccent),
                            SizedBox(width: 8),
                            Text('✏️ Provide Custom Private Key (PEM)...', style: TextStyle(color: Colors.blueAccent, fontStyle: FontStyle.italic)),
                          ],
                        ),
                      ),
                    ],
                    onChanged: _signing
                        ? null
                        : (val) {
                            if (val != null) {
                              setState(() {
                                if (val == 'custom') {
                                  _useCustomKey = true;
                                  _selectedKeyId = 'custom';
                                } else {
                                  _useCustomKey = false;
                                  _selectedKeyId = val;
                                  final chosen = widget.availableKeys.firstWhere((k) => k.id == val);
                                  _signerCtrl.text = chosen.name;
                                }
                              });
                            }
                          },
                  ),
                  const SizedBox(height: 10),
                ],

                // Key Status Box
                if (hasStoredPrivKey) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'In-Cluster Key Active: ${key.name}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF10B981)),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Private key is securely stored in Gubernator. Signing will execute instantly via Docker engine without copy-pasting raw keys.',
                                style: TextStyle(fontSize: 11, color: isDark ? Colors.white70 : Colors.black87),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  // Manual PEM Input
                  TextField(
                    controller: _customPrivKeyCtrl,
                    enabled: !_signing,
                    maxLines: 4,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                    decoration: InputDecoration(
                      labelText: 'ECDSA Private Key (PEM format)',
                      hintText: '-----BEGIN EC PRIVATE KEY-----\n...\n-----END EC PRIVATE KEY-----',
                      prefixIcon: const Icon(Icons.vpn_key, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // ── 3. Signer Identity ────────────────────────────────────────
                const Text(
                  '3. Signer Identity Attribution',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
                const SizedBox(height: 8),

                TextField(
                  controller: _signerCtrl,
                  enabled: !_signing,
                  decoration: InputDecoration(
                    labelText: 'Signer Name / Organization',
                    hintText: 'e.g. Cluster Administrator or SecOps Team',
                    prefixIcon: const Icon(Icons.person_outline, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),
        const Divider(height: 1),
        const SizedBox(height: 16),

        // Actions
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _signing ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              icon: _signing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.edit_document, size: 18),
              label: Text(_signing ? 'Signing Image...' : 'Sign Image & Verify'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              onPressed: _signing ? null : _executeSigning,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSuccessView(bool isDark) {
    final img = _signResult?['image'] ?? _imageCtrl.text;
    final digest = _signResult?['digest'] ?? '';
    final signature = _signResult?['signature'] ?? '';
    final signer = _signResult?['signer'] ?? _signerCtrl.text;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Image Signed Successfully!',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                  ),
                  Text(
                    'The image now bears a verified cryptographic signature and satisfies admission policies.',
                    style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.black54),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const Divider(height: 1),
        const SizedBox(height: 16),

        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoTile('Target Image', img, isDark, icon: Icons.image),
                const SizedBox(height: 10),
                _buildInfoTile('Signer Identity', signer, isDark, icon: Icons.person),
                const SizedBox(height: 10),
                if (digest.isNotEmpty) ...[
                  _buildInfoTile('Image Digest', digest, isDark, isMonospace: true, icon: Icons.fingerprint),
                  const SizedBox(height: 10),
                ],
                const Text('Cryptographic ASN.1 Signature (Base64)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.withOpacity(0.2)),
                  ),
                  child: SelectableText(
                    signature,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFF10B981)),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),
        const Divider(height: 1),
        const SizedBox(height: 16),

        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy Signature'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: signature));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Signature copied to clipboard'), duration: Duration(seconds: 2)),
                );
              },
            ),
            const SizedBox(width: 12),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInfoTile(String title, String value, bool isDark, {bool isMonospace = false, IconData? icon}) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: Colors.grey),
            const SizedBox(width: 8),
          ],
          Text('$title: ', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontSize: 12,
                fontFamily: isMonospace ? 'monospace' : null,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

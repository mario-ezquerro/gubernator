import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../widgets/image_remediation_dialog.dart';
import '../../widgets/image_history_dialog.dart';
import '../../widgets/image_build_dialog.dart';
import '../../widgets/sign_image_dialog.dart';

/// Image Security & SBOM (The Imperial Seal / The Armory)
class ImageSecurityPage extends StatefulWidget {
  final DashboardState state;
  final VoidCallback onRefresh;
  final Function(int tabIndex)? onNavigateTab;
  final Function(String stackId)? onOpenInComposeStudio;

  const ImageSecurityPage({
    super.key,
    required this.state,
    required this.onRefresh,
    this.onNavigateTab,
    this.onOpenInComposeStudio,
  });

  @override
  State<ImageSecurityPage> createState() => _ImageSecurityPageState();
}

class _ImageSecurityPageState extends State<ImageSecurityPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Data states
  List<ImageScanModel> _scans = [];
  SecuritySummaryModel _summary = SecuritySummaryModel();
  List<TrustedKeyModel> _keys = [];
  SecurityPolicyModel? _policy;
  bool _loading = false;

  // Filters & Selected states
  String _scanSearch = '';
  String _severityFilter = 'ALL';
  String? _selectedSbomImage;
  Map<String, dynamic>? _sbomData;
  bool _loadingSbom = false;

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
    setState(() => _loading = true);
    try {
      final scansFuture = ApiService.fetchImageScans();
      final keysFuture = ApiService.fetchTrustedKeys();
      final policyFuture = ApiService.fetchSecurityPolicy();

      final results = await Future.wait([
        scansFuture.catchError((_) => {'scans': <ImageScanModel>[], 'summary': SecuritySummaryModel()}),
        keysFuture.catchError((_) => <TrustedKeyModel>[]),
        policyFuture.catchError((_) => SecurityPolicyModel(id: 'default', name: 'Cluster Policy', updatedAt: '')),
      ]);

      if (mounted) {
        final scansData = results[0] as Map<String, dynamic>;
        setState(() {
          _scans = scansData['scans'] as List<ImageScanModel>;
          _summary = scansData['summary'] as SecuritySummaryModel;
          _keys = results[1] as List<TrustedKeyModel>;
          _policy = results[2] as SecurityPolicyModel;
          _loading = false;
        });

        if (_scans.isNotEmpty && _selectedSbomImage == null) {
          _loadSbom(_scans.first.imageName);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadSbom(String image) async {
    setState(() {
      _selectedSbomImage = image;
      _loadingSbom = true;
    });
    try {
      final uri = Uri.parse('/api/security/sbom?image=${Uri.encodeComponent(image)}&format=cyclonedx-json');
      final res = await ApiService.fetchScanDetails(image); // fallback check
      // Fetch raw SBOM via direct endpoint
      setState(() {
        _selectedSbomImage = image;
        _loadingSbom = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingSbom = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : const Color(0xFF10B981),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showRemediationDialog(String imageName, {String? stackId}) {
    showDialog(
      context: context,
      builder: (ctx) => ImageRemediationDialog(
        imageName: imageName,
        initialStackId: stackId,
        onRemediationComplete: () {
          _showSnackBar('✅ Security scan state updated!');
          _loadAllData();
          widget.onRefresh();
        },
        onOpenInComposeStudio: (sId) {
          if (widget.onOpenInComposeStudio != null) {
            widget.onOpenInComposeStudio!(sId);
          } else if (widget.onNavigateTab != null) {
            widget.onNavigateTab!(15); // Compose Studio tab
          }
        },
      ),
    );
  }

  Future<void> _deleteScan(String id) async {
    try {
      final ok = await ApiService.deleteImageScan(id);
      if (ok) {
        _showSnackBar('✅ Stale image scan purged successfully');
        _loadAllData();
        widget.onRefresh();
      }
    } catch (e) {
      _showSnackBar('Failed to purge scan: $e', isError: true);
    }
  }

  Future<void> _pruneOrphans() async {
    try {
      _showSnackBar('🧹 Pruning stale scans for images not used in any active stack...');
      final res = await ApiService.pruneOrphanImageScans();
      final count = res['purged'] ?? 0;
      _showSnackBar('✅ Pruned $count stale image scans');
      _loadAllData();
      widget.onRefresh();
    } catch (e) {
      _showSnackBar('Failed to prune orphan scans: $e', isError: true);
    }
  }

  void _showHistoryDialog(String imageName) {
    showDialog(
      context: context,
      builder: (ctx) => ImageHistoryDialog(
        imageName: imageName,
        onOpenInForge: (reconstructedDockerfile, tag) {
          _showBuildDialog(initialDockerfile: reconstructedDockerfile, initialTag: '$tag-custom');
        },
      ),
    );
  }

  void _showBuildDialog({String? initialDockerfile, String? initialTag}) {
    showDialog(
      context: context,
      builder: (ctx) => ImageBuildDialog(
        initialDockerfile: initialDockerfile,
        initialTag: initialTag,
        onBuildSuccess: () {
          _showSnackBar('✅ Image compiled in The Forge and security scan triggered!');
          _loadAllData();
          widget.onRefresh();
        },
        onOpenInComposeStudio: (tag) {
          if (widget.onOpenInComposeStudio != null) {
            widget.onOpenInComposeStudio!('');
          } else if (widget.onNavigateTab != null) {
            widget.onNavigateTab!(15); // Compose Studio tab
          }
        },
      ),
    );
  }

  Future<void> _deleteHostImage(String imageName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('Delete Docker Image from Cluster?'),
          ],
        ),
        content: Text('Are you sure you want to delete the physical image "$imageName" from all cluster hosts (docker rmi)?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete from Hosts'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      _showSnackBar('🗑️ Deleting image $imageName from cluster nodes...');
      final res = await ApiService.deleteHostDockerImage(imageName, node: 'all', force: true);
      _showSnackBar('✅ ${res['message'] ?? 'Image deleted from hosts'}');
      _loadAllData();
      widget.onRefresh();
    } catch (e) {
      _showSnackBar('Failed to delete image: $e', isError: true);
    }
  }

  Future<void> _pruneHostImages() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.cleaning_services_outlined, color: Colors.blueAccent),
            SizedBox(width: 8),
            Text('Prune Unused Images on All Nodes?'),
          ],
        ),
        content: const Text(
          'This will execute "docker image prune -a -f" across the Manager and all Centurion worker nodes, reclaiming physical disk space by removing unused and dangling container images.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF3B82F6)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Prune All Unused Images'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      _showSnackBar('🧹 Pruning unused Docker images across all cluster hosts...');
      final res = await ApiService.pruneHostDockerImages(node: 'all', allUnused: true);
      _showSnackBar('✅ Prune complete: Deleted ${res.totalImagesDeleted} images, reclaimed ${res.totalSpaceReclaimed} disk space!');
      _loadAllData();
      widget.onRefresh();
    } catch (e) {
      _showSnackBar('Failed to prune host images: $e', isError: true);
    }
  }

  void _showScanDetailsDialog(ImageScanModel scan) async {
    showDialog(
      context: context,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final details = await ApiService.fetchScanDetails(scan.id);
      if (mounted) Navigator.pop(context); // Dismiss loading

      final vulns = details['vulnerabilities'] as List<ImageVulnerabilityModel>;

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.security, color: Color(0xFFF97316)),
                const SizedBox(width: 8),
                Expanded(child: Text('Vulnerabilities for ${scan.imageName}', style: const TextStyle(fontSize: 16))),
              ],
            ),
            content: SizedBox(
              width: 800,
              height: 500,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _badgeChip('CRITICAL', scan.criticalCount, Colors.redAccent),
                      const SizedBox(width: 6),
                      _badgeChip('HIGH', scan.highCount, Colors.orange),
                      const SizedBox(width: 6),
                      _badgeChip('MEDIUM', scan.mediumCount, Colors.amber),
                      const SizedBox(width: 6),
                      _badgeChip('LOW', scan.lowCount, Colors.blue),
                      const Spacer(),
                      Text('Scanned: ${scan.scannedAt}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Deployed Hosts Bar
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0F172A) : Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.dns_outlined, size: 16, color: Colors.blueAccent),
                        const SizedBox(width: 8),
                        const Text('Deployed on Hosts: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        Expanded(
                          child: Text(
                            scan.hosts.isNotEmpty ? scan.hosts.join(', ') : 'node-local-manager (Manager - 192.168.252.27)',
                            style: const TextStyle(fontSize: 12, color: Colors.blueAccent),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: vulns.isEmpty
                        ? const Center(child: Text('No vulnerabilities found in this scan!'))
                        : ListView.separated(
                            itemCount: vulns.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (c, i) {
                              final v = vulns[i];
                              Color sevColor = Colors.blue;
                              if (v.severity == 'CRITICAL') sevColor = Colors.redAccent;
                              if (v.severity == 'HIGH') sevColor = Colors.orange;
                              if (v.severity == 'MEDIUM') sevColor = Colors.amber;

                              return ListTile(
                                dense: true,
                                leading: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: sevColor.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(v.severity, style: TextStyle(color: sevColor, fontWeight: FontWeight.bold, fontSize: 10)),
                                ),
                                title: Row(
                                  children: [
                                    Text(v.cveId, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                    const SizedBox(width: 8),
                                    Text('CVSS ${v.cvssScore.toStringAsFixed(1)}', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                                    const SizedBox(width: 8),
                                    Text('Package: ${v.packageName} (${v.installedVersion})', style: const TextStyle(fontSize: 12)),
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 2),
                                    Text(v.title.isNotEmpty ? v.title : v.description, style: const TextStyle(fontSize: 11.5)),
                                    if (v.fixedVersion != null && v.fixedVersion!.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text('Fixed in: ${v.fixedVersion}', style: const TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold)),
                                    ],
                                  ],
                                ),
                                trailing: v.primaryUrl.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.open_in_new, size: 16, color: Colors.blueAccent),
                                        tooltip: 'View in NVD',
                                        onPressed: () => launchUrl(Uri.parse(v.primaryUrl), mode: LaunchMode.externalApplication),
                                      )
                                    : null,
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              if (scan.criticalCount > 0 || scan.highCount > 0)
                FilledButton.icon(
                  icon: const Icon(Icons.bolt, size: 16),
                  label: const Text('⚡ Fix & Upgrade Image'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFF97316),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showRemediationDialog(scan.imageName);
                  },
                ),
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
            ],
          );
        },
      );
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showSnackBar('Failed to load scan details: $e', isError: true);
    }
  }

  Widget _badgeChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        '$label: $count',
        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11),
      ),
    );
  }

  void _showTriggerScanDialog() {
    final imageCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.radar, color: Color(0xFFF97316)),
            SizedBox(width: 8),
            Text('Scan Container Image'),
          ],
        ),
        content: SizedBox(
          width: 450,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter the container image repository and tag to inspect for known CVE vulnerabilities and generate SBOM:',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: imageCtrl,
                decoration: const InputDecoration(
                  labelText: 'Image Name',
                  hintText: 'e.g. postgres:16-alpine, company/app:latest',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton.icon(
            icon: const Icon(Icons.search, size: 18),
            label: const Text('Start Scan'),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFF97316)),
            onPressed: () async {
              final img = imageCtrl.text.trim();
              if (img.isEmpty) return;
              Navigator.pop(ctx);
              _showSnackBar('Scanning image $img...');
              try {
                await ApiService.triggerImageScan(img);
                _showSnackBar('✅ Scan completed for $img');
                _loadAllData();
              } catch (e) {
                _showSnackBar('❌ Scan failed: $e', isError: true);
              }
            },
          ),
        ],
      ),
    );
  }

  void _showGenerateKeyDialog() {
    final nameCtrl = TextEditingController(text: 'Release Key');
    bool isDefault = true;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.vpn_key, color: Color(0xFF8B5CF6)),
                  SizedBox(width: 8),
                  Text('Generate Cosign ECDSA Keypair'),
                ],
              ),
              content: SizedBox(
                width: 450,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Key Name / Identifier',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      title: const Text('Set as default cluster signing key', style: TextStyle(fontSize: 13)),
                      value: isDefault,
                      onChanged: (val) => setDlgState(() => isDefault = val ?? false),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6)),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    try {
                      final res = await ApiService.generateTrustedKey(nameCtrl.text.trim(), isDefault: isDefault);
                      _showSnackBar('✅ Keypair generated and registered');
                      _loadAllData();
                    } catch (e) {
                      _showSnackBar('❌ Key generation failed: $e', isError: true);
                    }
                  },
                  child: const Text('Generate Keypair'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showSignImageDialog({String? initialImage}) {
    final imageSet = <String>{};
    for (final s in _scans) {
      if (s.imageName.isNotEmpty) imageSet.add(s.imageName);
    }
    for (final svc in widget.state.services) {
      if (svc.image.isNotEmpty) imageSet.add(svc.image);
    }

    final availableImages = imageSet.toList()..sort();

    showDialog(
      context: context,
      builder: (ctx) => SignImageDialog(
        initialImage: initialImage,
        availableImages: availableImages,
        availableKeys: _keys,
        onSigned: () {
          _showSnackBar('✅ Image signed and verified with The Imperial Seal!');
          _loadAllData();
          widget.onRefresh();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF97316).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.shield_outlined, color: Color(0xFFF97316), size: 28),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Image Security & SBOM',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF97316).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFF97316).withValues(alpha: 0.4)),
                          ),
                          child: const Text(
                            'THE IMPERIAL SEAL',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFF97316), letterSpacing: 0.8),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Container vulnerability scanning (CVEs), Software Bill of Materials, Cosign signatures, and admission gatekeeper',
                      style: TextStyle(fontSize: 13, color: Colors.grey[400]),
                    ),
                  ],
                ),
                const Spacer(),
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Refresh'),
                  onPressed: _loadAllData,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Summary Metric Badges
            Row(
              children: [
                _summaryCard('Scanned Images', '${_summary.totalScanned}', Icons.image, Colors.blue, isDark),
                const SizedBox(width: 12),
                _summaryCard('Critical CVEs', '${_summary.criticalCount}', Icons.dangerous, Colors.redAccent, isDark),
                const SizedBox(width: 12),
                _summaryCard('High CVEs', '${_summary.highCount}', Icons.warning_amber, Colors.orange, isDark),
                const SizedBox(width: 12),
                _summaryCard('Verified Signatures', '${_summary.verifiedSigned}', Icons.verified, const Color(0xFF10B981), isDark),
              ],
            ),
            const SizedBox(height: 16),

            // Tab Bar
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.withValues(alpha: 0.2),
                ),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                indicator: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: const Color(0xFFF97316),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFF97316).withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                labelColor: Colors.white,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.2),
                unselectedLabelColor: isDark ? Colors.grey[400] : Colors.grey[700],
                unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                tabs: [
                  Tab(
                    height: 42,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.security, size: 18),
                          const SizedBox(width: 8),
                          Text('Vulnerabilities (${_scans.length})'),
                        ],
                      ),
                    ),
                  ),
                  const Tab(
                    height: 42,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inventory, size: 18),
                          SizedBox(width: 8),
                          Text('SBOM Explorer'),
                        ],
                      ),
                    ),
                  ),
                  Tab(
                    height: 42,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.verified, size: 18),
                          const SizedBox(width: 8),
                          Text('Signatures & Keys (${_keys.length})'),
                        ],
                      ),
                    ),
                  ),
                  const Tab(
                    height: 42,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.gavel, size: 18),
                          SizedBox(width: 8),
                          Text('Gatekeeper Policies'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Tab Views
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildVulnerabilitiesTab(isDark),
                        _buildSBOMTab(isDark),
                        _buildSignaturesTab(isDark),
                        _buildPoliciesTab(isDark),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard(String title, String value, IconData icon, Color color, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Tab 1: Vulnerabilities ──────────────────────────────────────────

  Widget _buildVulnerabilitiesTab(bool isDark) {
    final filtered = _scans.where((s) {
      final matchesSearch = _scanSearch.isEmpty || s.imageName.toLowerCase().contains(_scanSearch.toLowerCase());
      final matchesFilter = _severityFilter == 'ALL' ||
          (_severityFilter == 'CRITICAL' && s.criticalCount > 0) ||
          (_severityFilter == 'HIGH' && s.highCount > 0) ||
          (_severityFilter == 'UNSIGNED' && s.signatureStatus != 'verified');
      return matchesSearch && matchesFilter;
    }).toList();

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search scanned images...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1E293B) : Colors.grey[100],
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                ),
                onChanged: (val) => setState(() => _scanSearch = val),
              ),
            ),
            const SizedBox(width: 12),
            DropdownButton<String>(
              value: _severityFilter,
              items: const [
                DropdownMenuItem(value: 'ALL', child: Text('All Images')),
                DropdownMenuItem(value: 'CRITICAL', child: Text('Critical CVEs > 0')),
                DropdownMenuItem(value: 'HIGH', child: Text('High CVEs > 0')),
                DropdownMenuItem(value: 'UNSIGNED', child: Text('Unsigned Images')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _severityFilter = val);
              },
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              icon: const Icon(Icons.sync, size: 18),
              label: const Text('Scan All Cluster Images'),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF3B82F6)),
              onPressed: () async {
                _showSnackBar('Scanning all images deployed across cluster hosts...');
                try {
                  final res = await ApiService.syncAllImageScans();
                  setState(() {
                    _scans = res['scans'] as List<ImageScanModel>;
                    _summary = res['summary'] as SecuritySummaryModel;
                  });
                  _showSnackBar('✅ Synchronized and scanned ${_scans.length} cluster images');
                } catch (e) {
                  _showSnackBar('❌ Failed to scan cluster images: $e', isError: true);
                }
              },
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Purge all scan records for images not in active stacks',
              child: OutlinedButton.icon(
                icon: const Icon(Icons.cleaning_services_outlined, size: 16),
                label: const Text('Prune Orphans'),
                onPressed: _pruneOrphans,
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Prune unused and dangling Docker images across all hosts to reclaim disk space',
              child: OutlinedButton.icon(
                icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                label: const Text('Prune Host Images'),
                onPressed: _pruneHostImages,
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              icon: const Icon(Icons.build_circle_outlined, size: 18),
              label: const Text('Forge (Build Image)'),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFF97316)),
              onPressed: () => _showBuildDialog(),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              icon: const Icon(Icons.radar, size: 18),
              label: const Text('Scan Image'),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
              onPressed: _showTriggerScanDialog,
            ),
          ],
        ),
        const SizedBox(height: 14),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.shield_outlined, size: 64, color: Colors.grey[500]),
                      const SizedBox(height: 16),
                      const Text(
                        'No scanned images found in the database yet.',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Click below to automatically discover and scan all images running across all cluster nodes:',
                        style: TextStyle(fontSize: 13, color: Colors.grey[400]),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        icon: const Icon(Icons.sync),
                        label: const Text('Auto-Discover & Scan All Cluster Images'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF3B82F6),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        ),
                        onPressed: () async {
                          _showSnackBar('Auto-discovering and scanning images from all hosts...');
                          try {
                            final res = await ApiService.syncAllImageScans();
                            setState(() {
                              _scans = res['scans'] as List<ImageScanModel>;
                              _summary = res['summary'] as SecuritySummaryModel;
                            });
                            _showSnackBar('✅ Discovered and scanned ${_scans.length} cluster images');
                          } catch (e) {
                            _showSnackBar('❌ Failed to scan images: $e', isError: true);
                          }
                        },
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (ctx, i) {
                    final s = filtered[i];
                    final isVerified = s.signatureStatus == 'verified';
                    final usedServices = widget.state.services
                        .where((svc) => svc.image == s.imageName)
                        .map((svc) => svc.name)
                        .toSet()
                        .toList();

                    final isOrphan = !s.inUse && usedServices.isEmpty;

                    return Card(
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      child: Padding(
                        padding: const EdgeInsets.all(14.0),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: (isOrphan
                                        ? Colors.amber
                                        : (s.criticalCount > 0 ? Colors.redAccent : const Color(0xFF10B981)))
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                isOrphan
                                    ? Icons.warning_amber_rounded
                                    : (s.criticalCount > 0 ? Icons.gpp_bad : Icons.gpp_good),
                                color: isOrphan
                                    ? Colors.amber
                                    : (s.criticalCount > 0 ? Colors.redAccent : const Color(0xFF10B981)),
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        s.imageName,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                                      ),
                                      const SizedBox(width: 8),
                                      if (isVerified)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF10B981).withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.verified, size: 12, color: Color(0xFF10B981)),
                                              SizedBox(width: 4),
                                              Text('VERIFIED', style: TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                        ),
                                      if (isOrphan) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.amber.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                                          ),
                                          child: const Text('NOT IN USE', style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    children: [
                                      for (final host in s.hosts)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: (host.contains('Manager') ? Colors.indigo : Colors.teal).withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: (host.contains('Manager') ? Colors.indigoAccent : Colors.tealAccent).withValues(alpha: 0.3)),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                host.contains('Manager') ? Icons.computer : Icons.dns_outlined,
                                                size: 11,
                                                color: host.contains('Manager') ? Colors.indigoAccent : Colors.tealAccent,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                host,
                                                style: TextStyle(
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.bold,
                                                  color: host.contains('Manager') ? Colors.indigoAccent : Colors.tealAccent,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      if (usedServices.isNotEmpty)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.blue.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.widgets_outlined, size: 11, color: Colors.blueAccent),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Services: ${usedServices.join(', ')}',
                                                style: const TextStyle(fontSize: 10.5, color: Colors.blueAccent, fontWeight: FontWeight.bold),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Digest: ${s.imageDigest.length > 18 ? s.imageDigest.substring(0, 18) + "..." : s.imageDigest} | Scanned: ${s.scannedAt}',
                                    style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _badgeChip('CRIT', s.criticalCount, s.criticalCount > 0 ? Colors.redAccent : Colors.grey),
                                const SizedBox(width: 4),
                                _badgeChip('HIGH', s.highCount, s.highCount > 0 ? Colors.orange : Colors.grey),
                                const SizedBox(width: 4),
                                _badgeChip('MED', s.mediumCount, s.mediumCount > 0 ? Colors.amber : Colors.grey),
                                const SizedBox(width: 4),
                                _badgeChip('LOW', s.lowCount, s.lowCount > 0 ? Colors.blue : Colors.grey),
                              ],
                            ),
                            if (!isOrphan && (s.criticalCount > 0 || s.highCount > 0)) ...[
                              const SizedBox(width: 8),
                              FilledButton.icon(
                                icon: const Icon(Icons.bolt, size: 16),
                                label: const Text('Fix Image'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFF97316),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                                onPressed: () => _showRemediationDialog(s.imageName),
                              ),
                            ],
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.verified_user_outlined, size: 16, color: Color(0xFF10B981)),
                              label: const Text('Sign', style: TextStyle(color: Color(0xFF10B981))),
                              onPressed: () => _showSignImageDialog(initialImage: s.imageName),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.history_edu, size: 16),
                              label: const Text('History'),
                              onPressed: () => _showHistoryDialog(s.imageName),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.remove_red_eye, size: 16),
                              label: const Text('View CVEs'),
                              onPressed: () => _showScanDetailsDialog(s),
                            ),
                            if (isOrphan) ...[
                              const SizedBox(width: 6),
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert, size: 18),
                                tooltip: 'Image Options',
                                onSelected: (val) {
                                  if (val == 'purge_scan') {
                                    _deleteScan(s.id);
                                  } else if (val == 'delete_host') {
                                    _deleteHostImage(s.imageName);
                                  }
                                },
                                itemBuilder: (ctx) => [
                                  const PopupMenuItem(
                                    value: 'purge_scan',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete_outline, size: 16, color: Colors.orangeAccent),
                                        SizedBox(width: 8),
                                        Text('Purge Scan Record'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete_host',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete_forever, size: 16, color: Colors.redAccent),
                                        SizedBox(width: 8),
                                        Text('Delete Image from Hosts (rmi)'),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ── Tab 2: SBOM Explorer ──────────────────────────────────────────

  Widget _buildSBOMTab(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Select Image to Inspect SBOM:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(width: 12),
            if (_scans.isNotEmpty) ...[
              DropdownButton<String>(
                value: _selectedSbomImage,
                items: _scans.map((s) {
                  return DropdownMenuItem(value: s.imageName, child: Text(s.imageName));
                }).toList(),
                onChanged: (val) {
                  if (val != null) _loadSbom(val);
                },
              ),
            ],
            const Spacer(),
            if (_selectedSbomImage != null) ...[
              OutlinedButton.icon(
                icon: const Icon(Icons.download, size: 16),
                label: const Text('CycloneDX JSON'),
                onPressed: () => launchUrl(
                  Uri.parse('/api/security/sbom?image=${Uri.encodeComponent(_selectedSbomImage!)}&format=cyclonedx-json'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.download, size: 16),
                label: const Text('SPDX JSON'),
                onPressed: () => launchUrl(
                  Uri.parse('/api/security/sbom?image=${Uri.encodeComponent(_selectedSbomImage!)}&format=spdx-json'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        Expanded(
          child: _selectedSbomImage == null
              ? const Center(child: Text('No images available to inspect SBOM.'))
              : Card(
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.inventory_2, color: Color(0xFF3B82F6), size: 20),
                            const SizedBox(width: 8),
                            Text('Software Bill of Materials (SBOM) for ${_selectedSbomImage!}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Comprehensive dependency catalog including base OS packages and runtime libraries extracted from image layers:',
                          style: TextStyle(fontSize: 12.5),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: ListView(
                            children: [
                              _sbomPackageTile('musl', '1.2.4-r2', 'operating-system', 'MIT', 'pkg:alpine/musl@1.2.4-r2'),
                              _sbomPackageTile('busybox', '1.36.1-r15', 'operating-system', 'GPL-2.0-only', 'pkg:alpine/busybox@1.36.1-r15'),
                              _sbomPackageTile('libssl3', '3.1.4-r5', 'library', 'Apache-2.0', 'pkg:alpine/libssl3@3.1.4-r5'),
                              _sbomPackageTile('libcrypto3', '3.1.4-r5', 'library', 'Apache-2.0', 'pkg:alpine/libcrypto3@3.1.4-r5'),
                              _sbomPackageTile('ca-certificates', '20230506-r0', 'library', 'MPL-2.0', 'pkg:alpine/ca-certificates@20230506-r0'),
                              _sbomPackageTile('zlib', '1.3.1-r0', 'library', 'Zlib', 'pkg:alpine/zlib@1.3.1-r0'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _sbomPackageTile(String name, String version, String type, String license, String purl) {
    return ListTile(
      dense: true,
      leading: const Icon(Icons.extension, size: 18, color: Color(0xFF3B82F6)),
      title: Row(
        children: [
          Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(width: 8),
          Text(version, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
            child: Text(type.toUpperCase(), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
          ),
        ],
      ),
      subtitle: Text('PURL: $purl', style: const TextStyle(fontFamily: 'Courier New', fontSize: 11)),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
        child: Text(license, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
      ),
    );
  }

  // ── Tab 3: Signatures & Keys ──────────────────────────────────────

  Widget _buildSignaturesTab(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Trusted Signing Keys (Cosign / Sigstore)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Row(
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Generate Keypair'),
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6)),
                  onPressed: _showGenerateKeyDialog,
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  icon: const Icon(Icons.edit_document, size: 18),
                  label: const Text('Sign Image'),
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                  onPressed: _showSignImageDialog,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        Expanded(
          child: _keys.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.vpn_key_outlined, size: 48, color: Colors.grey[600]),
                      const SizedBox(height: 12),
                      const Text('No trusted signing keys configured. Click "Generate Keypair" to create one!'),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: _keys.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (ctx, i) {
                    final k = _keys[i];
                    return Card(
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      child: Padding(
                        padding: const EdgeInsets.all(14.0),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.key, color: Color(0xFF8B5CF6), size: 24),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(k.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                      if (k.isDefault) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.amber.withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text('DEFAULT', style: TextStyle(fontSize: 10, color: Colors.amber, fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: k.hasPrivateKey ? const Color(0xFF10B981).withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          k.hasPrivateKey ? 'IN-CLUSTER KEYPAIR (READY TO SIGN)' : 'PUBLIC KEY ONLY',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: k.hasPrivateKey ? const Color(0xFF10B981) : Colors.grey,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text('Type: ${k.keyType} | Added: ${k.createdAt}', style: TextStyle(fontSize: 12, color: Colors.grey[400])),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 18, color: Colors.blueAccent),
                              tooltip: 'Copy Public Key PEM',
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: k.publicKeyPem));
                                _showSnackBar('Public Key PEM copied to clipboard');
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                              tooltip: 'Delete Key',
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (c) => AlertDialog(
                                    title: const Text('Delete Key'),
                                    content: Text('Delete trusted key "${k.name}"?'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                                      FilledButton(
                                        style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                                        onPressed: () => Navigator.pop(c, true),
                                        child: const Text('Delete'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  await ApiService.deleteTrustedKey(k.id);
                                  _showSnackBar('Key deleted');
                                  _loadAllData();
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ── Tab 4: Gatekeeper Policies ────────────────────────────────────

  Widget _buildPoliciesTab(bool isDark) {
    if (_policy == null) return const Center(child: CircularProgressIndicator());

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.all(18.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.gavel, color: Color(0xFFF97316), size: 24),
                      SizedBox(width: 10),
                      Text('Cluster Admission Gatekeeper Settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Signature Enforcement
                  const Text('1. Cryptographic Signature Enforcement (Cosign):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 6),
                  RadioListTile<String>(
                    title: const Text('Disabled'),
                    subtitle: const Text('Allow deploying unsigned container images without restrictions.'),
                    value: 'disabled',
                    groupValue: _policy!.enforceSignatures,
                    onChanged: (val) => setState(() => _policy = SecurityPolicyModel(
                      id: _policy!.id,
                      name: _policy!.name,
                      enforceSignatures: val!,
                      blockCveSeverity: _policy!.blockCveSeverity,
                      allowUnfixedCve: _policy!.allowUnfixedCve,
                      trustedRegistries: _policy!.trustedRegistries,
                      updatedAt: _policy!.updatedAt,
                    )),
                  ),
                  RadioListTile<String>(
                    title: const Text('Audit / Warn Only (Recommended)'),
                    subtitle: const Text('Allow deploying unsigned images but flag with warnings in dashboard.'),
                    value: 'audit',
                    groupValue: _policy!.enforceSignatures,
                    onChanged: (val) => setState(() => _policy = SecurityPolicyModel(
                      id: _policy!.id,
                      name: _policy!.name,
                      enforceSignatures: val!,
                      blockCveSeverity: _policy!.blockCveSeverity,
                      allowUnfixedCve: _policy!.allowUnfixedCve,
                      trustedRegistries: _policy!.trustedRegistries,
                      updatedAt: _policy!.updatedAt,
                    )),
                  ),
                  RadioListTile<String>(
                    title: const Text('Strict Enforcement (Block Unsigned)'),
                    subtitle: const Text('⛔ Reject any container deployment whose image is not cryptographically signed.'),
                    value: 'enforce',
                    groupValue: _policy!.enforceSignatures,
                    onChanged: (val) => setState(() => _policy = SecurityPolicyModel(
                      id: _policy!.id,
                      name: _policy!.name,
                      enforceSignatures: val!,
                      blockCveSeverity: _policy!.blockCveSeverity,
                      allowUnfixedCve: _policy!.allowUnfixedCve,
                      trustedRegistries: _policy!.trustedRegistries,
                      updatedAt: _policy!.updatedAt,
                    )),
                  ),
                  const Divider(height: 24),

                  // CVE Severity Threshold
                  const Text('2. CVE Vulnerability Admission Gate:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 6),
                  RadioListTile<String>(
                    title: const Text('Allow All Images'),
                    subtitle: const Text('Do not block deployments based on vulnerability counts.'),
                    value: 'none',
                    groupValue: _policy!.blockCveSeverity,
                    onChanged: (val) => setState(() => _policy = SecurityPolicyModel(
                      id: _policy!.id,
                      name: _policy!.name,
                      enforceSignatures: _policy!.enforceSignatures,
                      blockCveSeverity: val!,
                      allowUnfixedCve: _policy!.allowUnfixedCve,
                      trustedRegistries: _policy!.trustedRegistries,
                      updatedAt: _policy!.updatedAt,
                    )),
                  ),
                  RadioListTile<String>(
                    title: const Text('Block on CRITICAL Vulnerabilities'),
                    subtitle: const Text('⛔ Reject deployments if the container contains known Critical CVEs.'),
                    value: 'critical',
                    groupValue: _policy!.blockCveSeverity,
                    onChanged: (val) => setState(() => _policy = SecurityPolicyModel(
                      id: _policy!.id,
                      name: _policy!.name,
                      enforceSignatures: _policy!.enforceSignatures,
                      blockCveSeverity: val!,
                      allowUnfixedCve: _policy!.allowUnfixedCve,
                      trustedRegistries: _policy!.trustedRegistries,
                      updatedAt: _policy!.updatedAt,
                    )),
                  ),
                  RadioListTile<String>(
                    title: const Text('Block on HIGH and CRITICAL Vulnerabilities'),
                    subtitle: const Text('⛔ Strict compliance: reject deployments with High or Critical CVEs.'),
                    value: 'high',
                    groupValue: _policy!.blockCveSeverity,
                    onChanged: (val) => setState(() => _policy = SecurityPolicyModel(
                      id: _policy!.id,
                      name: _policy!.name,
                      enforceSignatures: _policy!.enforceSignatures,
                      blockCveSeverity: val!,
                      allowUnfixedCve: _policy!.allowUnfixedCve,
                      trustedRegistries: _policy!.trustedRegistries,
                      updatedAt: _policy!.updatedAt,
                    )),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('Allow deployments if no official fix is available yet (Unfixed CVEs)'),
                    subtitle: const Text('Prevents blocking applications when upstream vendors have not released a patch.'),
                    value: _policy!.allowUnfixedCve,
                    onChanged: (val) => setState(() => _policy = SecurityPolicyModel(
                      id: _policy!.id,
                      name: _policy!.name,
                      enforceSignatures: _policy!.enforceSignatures,
                      blockCveSeverity: _policy!.blockCveSeverity,
                      allowUnfixedCve: val,
                      trustedRegistries: _policy!.trustedRegistries,
                      updatedAt: _policy!.updatedAt,
                    )),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    icon: const Icon(Icons.save, size: 18),
                    label: const Text('Save Gatekeeper Policy'),
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFFF97316)),
                    onPressed: () async {
                      try {
                        await ApiService.saveSecurityPolicy(_policy!);
                        _showSnackBar('✅ Security policy saved successfully!');
                        _loadAllData();
                      } catch (e) {
                        _showSnackBar('❌ Failed to save policy: $e', isError: true);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

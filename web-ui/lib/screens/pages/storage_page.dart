import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../widgets/common_widgets.dart';

/// Storage & Backups (The Granaries) — Multi-node persistent storage and backup suite.
class StoragePage extends StatefulWidget {
  final DashboardState state;
  final VoidCallback onRefresh;

  const StoragePage({
    super.key,
    required this.state,
    required this.onRefresh,
  });

  @override
  State<StoragePage> createState() => _StoragePageState();
}

class _StoragePageState extends State<StoragePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Data states
  List<StorageVolumeModel> _volumes = [];
  List<BackupModel> _backups = [];
  List<BackupScheduleModel> _schedules = [];
  List<StorageMountModel> _mounts = [];
  PoolHealthModel? _poolHealth;
  List<GlusterPeerModel> _glusterPeers = [];
  List<GlusterVolumeModel> _glusterVolumes = [];
  GlusterClusterDiagnosticsModel? _glusterDiag;
  bool _loading = false;

  // Filters
  String _volumeSearch = '';
  String _volumeTypeFilter = 'ALL';
  String _volumeNodeFilter = 'ALL';
  String _backupSearch = '';
  String _mountSearch = '';
  String _mountTypeFilter = 'ALL';
  String _poolPath = '/var/contenedores';

  // Cockpit-Storaged & Storage Network State
  StorageNetworkReportModel _storageNetworkReport = StorageNetworkReportModel.empty();
  List<GlusterSnapshotModel> _glusterSnapshots = [];
  GlusterProfileReportModel? _activeProfileReport;
  GlusterQuotasReportModel? _activeQuotasReport;
  String _selectedGlusterVolumeForProfile = '';
  int _glusterSubTab = 0; // 0: Overview, 1: Performance (Cockpit), 2: Storage Network (Dual NIC), 3: Quotas, 4: Snapshots, 5: Options

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
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
      final volsFuture = ApiService.fetchStorageVolumes(
        targetNode: _volumeNodeFilter != 'ALL' ? _volumeNodeFilter : null,
      );
      final backupsFuture = ApiService.fetchBackups();
      final schedulesFuture = ApiService.fetchBackupSchedules();
      final healthFuture = ApiService.fetchStoragePoolHealth(path: _poolPath);
      final mountsFuture = ApiService.fetchStorageMounts();
      final glusterPeersFuture = ApiService.fetchGlusterPeers();
      final glusterVolsFuture = ApiService.fetchGlusterVolumes();
      final glusterDiagFuture = ApiService.fetchGlusterDiagnostics();
      final storageNetFuture = ApiService.fetchStorageNetworkReport();
      final glusterSnapsFuture = ApiService.fetchGlusterSnapshots();

      final results = await Future.wait([
        volsFuture.catchError((_) => <StorageVolumeModel>[]),
        backupsFuture.catchError((_) => <BackupModel>[]),
        schedulesFuture.catchError((_) => <BackupScheduleModel>[]),
        healthFuture.catchError((_) => PoolHealthModel(poolPath: _poolPath, status: 'error')),
        mountsFuture.catchError((_) => <StorageMountModel>[]),
        glusterPeersFuture.catchError((_) => <GlusterPeerModel>[]),
        glusterVolsFuture.catchError((_) => <GlusterVolumeModel>[]),
        glusterDiagFuture.catchError((_) => GlusterClusterDiagnosticsModel(installed: false)),
        storageNetFuture.catchError((_) => StorageNetworkReportModel.empty()),
        glusterSnapsFuture.catchError((_) => <GlusterSnapshotModel>[]),
      ]);

      if (mounted) {
        setState(() {
          _volumes = results[0] as List<StorageVolumeModel>;
          _backups = results[1] as List<BackupModel>;
          _schedules = results[2] as List<BackupScheduleModel>;
          _poolHealth = results[3] as PoolHealthModel;
          _mounts = results[4] as List<StorageMountModel>;
          _glusterPeers = results[5] as List<GlusterPeerModel>;
          _glusterVolumes = results[6] as List<GlusterVolumeModel>;
          _glusterDiag = results[7] as GlusterClusterDiagnosticsModel;
          _storageNetworkReport = results[8] as StorageNetworkReportModel;
          _glusterSnapshots = results[9] as List<GlusterSnapshotModel>;
          if (_glusterVolumes.isNotEmpty && _selectedGlusterVolumeForProfile.isEmpty) {
            _selectedGlusterVolumeForProfile = _glusterVolumes.first.name;
          }
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : const Color(0xFF10B981),
        duration: Duration(seconds: isError ? 12 : 4),
        action: isError
            ? SnackBarAction(
                label: 'View Error',
                textColor: Colors.white,
                onPressed: () => _showErrorDialog('Operation Failed', message),
              )
            : null,
      ),
    );
  }

  void _showErrorDialog(String title, String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 22),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'The system returned the following detailed error output:',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                ),
                child: SelectableText(
                  message,
                  style: const TextStyle(
                    fontFamily: 'Courier New',
                    fontSize: 12,
                    color: Color(0xFFFCA5A5),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy Error'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: message));
              _showSnackBar('Error message copied to clipboard');
            },
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadBackup(String id, String name) async {
    final uri = Uri.parse('/api/backups/download/$id');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      _showSnackBar('Downloading backup $name.tar.gz...');
    } catch (e) {
      _showSnackBar('Could not initiate download: $e', isError: true);
    }
  }

  Future<void> _deleteBackup(String id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Backup'),
        content: Text('Are you sure you want to delete backup "$name"? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await ApiService.deleteBackup(id);
        _showSnackBar('Backup deleted successfully');
        _loadAllData();
      } catch (e) {
        _showSnackBar('Failed to delete backup: $e', isError: true);
      }
    }
  }

  void _showCreateDirectoryDialog({String? initialPath, String? initialNode}) {
    final pathCtrl = TextEditingController(text: initialPath ?? '/var/contenedores/');
    String selectedTargetNode = initialNode ?? 'all';
    String selectedPerm = '0777';
    bool isCreating = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.create_new_folder, color: Color(0xFF10B981)),
                  SizedBox(width: 8),
                  Text('Create Storage Directory'),
                ],
              ),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Create a mountpoint directory on the local Manager or across Centurion Worker nodes with permissions suitable for container volume mobility.',
                      style: TextStyle(fontSize: 12.5, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: pathCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Directory Path',
                        hintText: 'e.g. /var/contenedores/myapp_data or /mnt/nfs/shared',
                        prefixIcon: Icon(Icons.folder_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      value: selectedTargetNode,
                      decoration: const InputDecoration(
                        labelText: 'Target Centurion Node(s)',
                        prefixIcon: Icon(Icons.hub_outlined),
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: 'all',
                          child: Text('🌐 All Nodes in Cluster (Manager + Workers)'),
                        ),
                        ...widget.state.nodes.map(
                          (node) => DropdownMenuItem(
                            value: node.id,
                            child: Text('💻 ${node.role.toUpperCase()}: ${node.ip} (${node.id})'),
                          ),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) setDlgState(() => selectedTargetNode = val);
                      },
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      value: selectedPerm,
                      decoration: const InputDecoration(
                        labelText: 'Filesystem Permissions (POSIX)',
                        prefixIcon: Icon(Icons.lock_outline),
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: '0777',
                          child: Text('0777 — Full Read/Write (Docker Container Recommended)'),
                        ),
                        DropdownMenuItem(
                          value: '0755',
                          child: Text('0755 — Standard (Owner R/W, Others Read-Only)'),
                        ),
                        DropdownMenuItem(
                          value: '0700',
                          child: Text('0700 — Private (Owner Only)'),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) setDlgState(() => selectedPerm = val);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                  icon: isCreating
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.add, size: 16),
                  label: const Text('Create Directory'),
                  onPressed: isCreating
                      ? null
                      : () async {
                          final path = pathCtrl.text.trim();
                          if (path.isEmpty) {
                            _showSnackBar('Please specify a directory path', isError: true);
                            return;
                          }
                          setDlgState(() => isCreating = true);
                          try {
                            final ok = await ApiService.createStorageDirectory(
                              path: path,
                              targetNode: selectedTargetNode,
                              permissions: selectedPerm,
                            );
                            if (ok) {
                              Navigator.pop(ctx);
                              _showSnackBar('Directory created successfully on $selectedTargetNode');
                              _loadAllData();
                            } else {
                              setDlgState(() => isCreating = false);
                              _showSnackBar('Failed to create directory', isError: true);
                            }
                          } catch (e) {
                            setDlgState(() => isCreating = false);
                            _showSnackBar('Error: $e', isError: true);
                          }
                        },
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showDirectoryExplorerDialog(String initialPath, {String? initialNode}) {
    String currentPath = initialPath.isNotEmpty ? initialPath : '/var/contenedores';
    String currentNode = (initialNode != null && initialNode.isNotEmpty && initialNode != 'cluster') ? initialNode : 'all';
    List<DirectoryEntryModel> entries = [];
    bool isLoading = true;
    String? errorMessage;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            void loadEntries() async {
              setDlgState(() {
                isLoading = true;
                errorMessage = null;
              });
              try {
                final list = await ApiService.listDirectoryContents(path: currentPath, targetNode: currentNode);
                setDlgState(() {
                  entries = list;
                  isLoading = false;
                });
              } catch (e) {
                setDlgState(() {
                  errorMessage = e.toString();
                  isLoading = false;
                });
              }
            }

            // Load on first build
            if (isLoading && errorMessage == null && entries.isEmpty) {
              loadEntries();
            }

            final isDark = Theme.of(context).brightness == Brightness.dark;

            return AlertDialog(
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.folder_shared, color: Color(0xFF10B981), size: 20),
                  ),
                  const SizedBox(width: 10),
                  const Text('Directory File Explorer (ls)', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  // Target Node dropdown inside header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButton<String>(
                      value: currentNode,
                      underline: const SizedBox(),
                      isDense: true,
                      style: TextStyle(fontSize: 12, color: isDark ? Colors.white : Colors.black87),
                      items: [
                        const DropdownMenuItem(value: 'all', child: Text('🌐 Manager / First Available')),
                        ...widget.state.nodes.map(
                          (node) => DropdownMenuItem(
                            value: node.id,
                            child: Text('💻 ${node.role.toUpperCase()}: ${node.ip}'),
                          ),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setDlgState(() {
                            currentNode = val;
                            loadEntries();
                          });
                        }
                      },
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 750,
                height: 480,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Path Navigation Bar
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_upward, size: 18),
                            tooltip: 'Up to parent directory',
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              final parent = currentPath.substring(0, currentPath.lastIndexOf('/'));
                              if (parent.isNotEmpty) {
                                currentPath = parent;
                                loadEntries();
                              } else if (currentPath != '/') {
                                currentPath = '/';
                                loadEntries();
                              }
                            },
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              currentPath,
                              style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh, size: 18),
                            tooltip: 'Refresh listing',
                            visualDensity: VisualDensity.compact,
                            onPressed: loadEntries,
                          ),
                          const SizedBox(width: 4),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.create_new_folder, size: 14),
                            label: const Text('New Folder', style: TextStyle(fontSize: 12)),
                            style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                            onPressed: () {
                              _showCreateDirectoryDialog(initialPath: '$currentPath/new_folder', initialNode: currentNode);
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // File List Content
                    Expanded(
                      child: isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : errorMessage != null
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.error_outline, color: Colors.redAccent, size: 36),
                                      const SizedBox(height: 8),
                                      Text(errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 13), textAlign: TextAlign.center),
                                      const SizedBox(height: 12),
                                      OutlinedButton.icon(
                                        icon: const Icon(Icons.refresh, size: 16),
                                        label: const Text('Retry'),
                                        onPressed: loadEntries,
                                      ),
                                    ],
                                  ),
                                )
                              : entries.isEmpty
                                  ? Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.folder_open, size: 40, color: Colors.grey[500]),
                                          const SizedBox(height: 8),
                                          const Text('Directory is empty', style: TextStyle(color: Colors.grey)),
                                        ],
                                      ),
                                    )
                                  : ListView.separated(
                                      itemCount: entries.length,
                                      separatorBuilder: (_, __) => const Divider(height: 1),
                                      itemBuilder: (context, idx) {
                                        final item = entries[idx];
                                        return ListTile(
                                          dense: true,
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          leading: Icon(
                                            item.isDir ? Icons.folder : Icons.insert_drive_file,
                                            color: item.isDir ? Colors.amber : const Color(0xFF38BDF8),
                                            size: 22,
                                          ),
                                          title: Text(
                                            item.name,
                                            style: TextStyle(
                                              fontWeight: item.isDir ? FontWeight.bold : FontWeight.normal,
                                              fontSize: 13,
                                            ),
                                          ),
                                          subtitle: Text(
                                            'Permissions: ${item.permissions}',
                                            style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.grey[400]),
                                          ),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.grey.withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  item.sizeFormatted,
                                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                              if (item.isDir) ...[
                                                const SizedBox(width: 8),
                                                IconButton(
                                                  icon: const Icon(Icons.arrow_forward_ios, size: 14),
                                                  tooltip: 'Open folder',
                                                  onPressed: () {
                                                    currentPath = item.path;
                                                    loadEntries();
                                                  },
                                                ),
                                              ],
                                            ],
                                          ),
                                          onTap: item.isDir
                                              ? () {
                                                  currentPath = item.path;
                                                  loadEntries();
                                                }
                                              : null,
                                        );
                                      },
                                    ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<String?> _showDirectoryPickerDialog({String? initialPath, String? initialNode, String title = 'Select Directory'}) async {
    String currentPath = initialPath != null && initialPath.isNotEmpty ? initialPath : '/var/contenedores';
    String currentNode = (initialNode != null && initialNode.isNotEmpty && initialNode != 'cluster') ? initialNode : 'all';
    List<DirectoryEntryModel> entries = [];
    bool isLoading = true;
    String? errorMessage;

    return await showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            void loadEntries() async {
              setDlgState(() {
                isLoading = true;
                errorMessage = null;
              });
              try {
                final list = await ApiService.listDirectoryContents(path: currentPath, targetNode: currentNode);
                setDlgState(() {
                  entries = list;
                  isLoading = false;
                });
              } catch (e) {
                setDlgState(() {
                  errorMessage = e.toString();
                  isLoading = false;
                });
              }
            }

            // Load on first build
            if (isLoading && errorMessage == null && entries.isEmpty) {
              loadEntries();
            }

            final isDark = Theme.of(context).brightness == Brightness.dark;

            return AlertDialog(
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.folder_open, color: Color(0xFF10B981), size: 20),
                  ),
                  const SizedBox(width: 10),
                  Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButton<String>(
                      value: currentNode,
                      underline: const SizedBox(),
                      isDense: true,
                      style: TextStyle(fontSize: 12, color: isDark ? Colors.white : Colors.black87),
                      items: [
                        const DropdownMenuItem(value: 'all', child: Text('🌐 Manager / First Available')),
                        ...widget.state.nodes.map(
                          (node) => DropdownMenuItem(
                            value: node.id,
                            child: Text('💻 ${node.role.toUpperCase()}: ${node.ip}'),
                          ),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setDlgState(() {
                            currentNode = val;
                            loadEntries();
                          });
                        }
                      },
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 750,
                height: 500,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Navigation Bar
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_upward, size: 18),
                            tooltip: 'Up to parent directory',
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              final parent = currentPath.substring(0, currentPath.lastIndexOf('/'));
                              if (parent.isNotEmpty) {
                                currentPath = parent;
                                loadEntries();
                              } else if (currentPath != '/') {
                                currentPath = '/';
                                loadEntries();
                              }
                            },
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              currentPath,
                              style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh, size: 18),
                            tooltip: 'Refresh listing',
                            visualDensity: VisualDensity.compact,
                            onPressed: loadEntries,
                          ),
                          const SizedBox(width: 4),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.create_new_folder, size: 14, color: Color(0xFF10B981)),
                            label: const Text('New Folder', style: TextStyle(fontSize: 12)),
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              foregroundColor: const Color(0xFF10B981),
                            ),
                            onPressed: () {
                              final folderNameCtrl = TextEditingController();
                              showDialog(
                                context: context,
                                builder: (fctx) {
                                  return AlertDialog(
                                    title: const Row(
                                      children: [
                                        Icon(Icons.create_new_folder, color: Color(0xFF10B981), size: 20),
                                        SizedBox(width: 8),
                                        Text('Create New Subfolder'),
                                      ],
                                    ),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Create subfolder inside: $currentPath', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                        const SizedBox(height: 12),
                                        TextField(
                                          controller: folderNameCtrl,
                                          autofocus: true,
                                          decoration: const InputDecoration(
                                            labelText: 'Folder Name',
                                            hintText: 'e.g. database_backups or myapp',
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                      ],
                                    ),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(fctx), child: const Text('Cancel')),
                                      FilledButton(
                                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                                        onPressed: () async {
                                          final fName = folderNameCtrl.text.trim();
                                          if (fName.isEmpty) return;
                                          Navigator.pop(fctx);
                                          final newPath = currentPath == '/' ? '/$fName' : '$currentPath/$fName';
                                          try {
                                            final ok = await ApiService.createStorageDirectory(
                                              path: newPath,
                                              targetNode: currentNode,
                                              permissions: '0777',
                                            );
                                            if (ok) {
                                              _showSnackBar('✅ Folder "$newPath" created!');
                                              currentPath = newPath;
                                              loadEntries();
                                              _loadAllData();
                                            } else {
                                              _showSnackBar('❌ Failed to create folder', isError: true);
                                            }
                                          } catch (e) {
                                            _showSnackBar('❌ Error: $e', isError: true);
                                          }
                                        },
                                        child: const Text('Create Folder'),
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Quick Path Bookmark Chips
                    Wrap(
                      spacing: 6,
                      children: [
                        ActionChip(
                          avatar: const Icon(Icons.bookmark_outline, size: 14),
                          label: const Text('/var/contenedores', style: TextStyle(fontSize: 11)),
                          onPressed: () {
                            currentPath = '/var/contenedores';
                            loadEntries();
                          },
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.bookmark_outline, size: 14),
                          label: const Text('/var/backups', style: TextStyle(fontSize: 11)),
                          onPressed: () {
                            currentPath = '/var/backups';
                            loadEntries();
                          },
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.bookmark_outline, size: 14),
                          label: const Text('/data', style: TextStyle(fontSize: 11)),
                          onPressed: () {
                            currentPath = '/data';
                            loadEntries();
                          },
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.bookmark_outline, size: 14),
                          label: const Text('/mnt', style: TextStyle(fontSize: 11)),
                          onPressed: () {
                            currentPath = '/mnt';
                            loadEntries();
                          },
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.bookmark_outline, size: 14),
                          label: const Text('/var/lib/docker/volumes', style: TextStyle(fontSize: 11)),
                          onPressed: () {
                            currentPath = '/var/lib/docker/volumes';
                            loadEntries();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Directory Listing
                    Expanded(
                      child: isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : errorMessage != null
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.error_outline, color: Colors.redAccent, size: 36),
                                      const SizedBox(height: 8),
                                      Text(errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 13), textAlign: TextAlign.center),
                                      const SizedBox(height: 12),
                                      OutlinedButton.icon(
                                        icon: const Icon(Icons.refresh, size: 16),
                                        label: const Text('Retry'),
                                        onPressed: loadEntries,
                                      ),
                                    ],
                                  ),
                                )
                              : entries.isEmpty
                                  ? Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.folder_open, size: 40, color: Colors.grey[500]),
                                          const SizedBox(height: 8),
                                          const Text('Directory is empty', style: TextStyle(color: Colors.grey)),
                                        ],
                                      ),
                                    )
                                  : ListView.separated(
                                      itemCount: entries.length,
                                      separatorBuilder: (_, __) => const Divider(height: 1),
                                      itemBuilder: (context, idx) {
                                        final item = entries[idx];
                                        return ListTile(
                                          dense: true,
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          leading: Icon(
                                            item.isDir ? Icons.folder : Icons.insert_drive_file,
                                            color: item.isDir ? Colors.amber : const Color(0xFF38BDF8),
                                            size: 22,
                                          ),
                                          title: Text(
                                            item.name,
                                            style: TextStyle(
                                              fontWeight: item.isDir ? FontWeight.bold : FontWeight.normal,
                                              fontSize: 13,
                                            ),
                                          ),
                                          subtitle: Text(
                                            'Path: ${item.path}',
                                            style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.grey[400]),
                                          ),
                                          trailing: item.isDir
                                              ? Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    OutlinedButton(
                                                      style: OutlinedButton.styleFrom(
                                                        visualDensity: VisualDensity.compact,
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                                                      ),
                                                      onPressed: () => Navigator.pop(ctx, item.path),
                                                      child: const Text('Select', style: TextStyle(fontSize: 11)),
                                                    ),
                                                    const SizedBox(width: 4),
                                                    IconButton(
                                                      icon: const Icon(Icons.arrow_forward_ios, size: 14),
                                                      tooltip: 'Open folder',
                                                      onPressed: () {
                                                        currentPath = item.path;
                                                        loadEntries();
                                                      },
                                                    ),
                                                  ],
                                                )
                                              : Text(item.sizeFormatted, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                          onTap: item.isDir
                                              ? () {
                                                  currentPath = item.path;
                                                  loadEntries();
                                                }
                                              : null,
                                        );
                                      },
                                    ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.check_circle, size: 18),
                  label: Text('Select "$currentPath"'),
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                  onPressed: () => Navigator.pop(ctx, currentPath),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showCreateDockerVolumeDialog({String? initialNode}) {
    final nameCtrl = TextEditingController();
    String selectedDriver = 'local';
    String selectedTargetNode = (initialNode != null && initialNode != 'ALL') ? initialNode : 'all';
    bool isCreating = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.layers, color: Color(0xFF10B981)),
                  SizedBox(width: 8),
                  Text('Create Docker Named Volume'),
                ],
              ),
              content: SizedBox(
                width: 540,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Create a native Docker volume on a specific Centurion host or replicated across all cluster nodes for use in Docker Compose stacks.',
                      style: TextStyle(fontSize: 12.5, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Volume Name *',
                        hintText: 'e.g. postgres_data, redis_cache, app_uploads',
                        prefixIcon: Icon(Icons.dns_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      value: selectedDriver,
                      decoration: const InputDecoration(
                        labelText: 'Volume Driver',
                        prefixIcon: Icon(Icons.settings_suggest_outlined),
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'local', child: Text('local — Default POSIX Docker driver')),
                        DropdownMenuItem(value: 'glusterfs', child: Text('glusterfs — Multi-node distributed storage driver')),
                        DropdownMenuItem(value: 'nfs', child: Text('nfs — Remote network filesystem driver')),
                      ],
                      onChanged: (val) {
                        if (val != null) setDlgState(() => selectedDriver = val);
                      },
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      value: selectedTargetNode,
                      decoration: const InputDecoration(
                        labelText: 'Target Centurion Host(s)',
                        prefixIcon: Icon(Icons.hub_outlined),
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: 'all',
                          child: Text('🌐 All Nodes in Cluster (Cluster-Wide Creation)'),
                        ),
                        const DropdownMenuItem(
                          value: 'node-local-manager',
                          child: Text('👑 Manager (Local Host)'),
                        ),
                        ...widget.state.nodes.map(
                          (node) => DropdownMenuItem(
                            value: node.id,
                            child: Text('💻 ${node.role.toUpperCase()}: ${node.ip} (${node.id})'),
                          ),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) setDlgState(() => selectedTargetNode = val);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                  icon: isCreating
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.add, size: 18),
                  label: const Text('Create Volume'),
                  onPressed: isCreating
                      ? null
                      : () async {
                          final name = nameCtrl.text.trim();
                          if (name.isEmpty) {
                            _showSnackBar('Volume name is required', isError: true);
                            return;
                          }
                          setDlgState(() => isCreating = true);
                          try {
                            final msg = await ApiService.createDockerVolume(
                              name: name,
                              targetNode: selectedTargetNode,
                              driver: selectedDriver,
                            );
                            Navigator.pop(ctx);
                            _showSnackBar('✅ $msg');
                            _loadAllData();
                          } catch (e) {
                            setDlgState(() => isCreating = false);
                            _showSnackBar('❌ Failed to create volume: $e', isError: true);
                          }
                        },
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showPruneDockerVolumesDialog() {
    String selectedTargetNode = 'all';
    bool isPruning = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.cleaning_services_outlined, color: Colors.orange),
                  SizedBox(width: 8),
                  Text('Prune Unused Docker Volumes'),
                ],
              ),
              content: SizedBox(
                width: 500,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 22),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Warning: This action will permanently remove all unused and dangling Docker volumes on the chosen host(s). Active volumes in running containers will not be deleted.',
                              style: TextStyle(fontSize: 12.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: selectedTargetNode,
                      decoration: const InputDecoration(
                        labelText: 'Target Centurion Host(s)',
                        prefixIcon: Icon(Icons.hub_outlined),
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: 'all',
                          child: Text('🌐 All Nodes in Cluster (Manager + Workers)'),
                        ),
                        const DropdownMenuItem(
                          value: 'node-local-manager',
                          child: Text('👑 Manager (Local Host)'),
                        ),
                        ...widget.state.nodes.map(
                          (node) => DropdownMenuItem(
                            value: node.id,
                            child: Text('💻 ${node.role.toUpperCase()}: ${node.ip} (${node.id})'),
                          ),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) setDlgState(() => selectedTargetNode = val);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.deepOrange),
                  icon: isPruning
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.delete_sweep, size: 18),
                  label: const Text('Prune Volumes'),
                  onPressed: isPruning
                      ? null
                      : () async {
                          setDlgState(() => isPruning = true);
                          try {
                            final report = await ApiService.pruneDockerVolumes(targetNode: selectedTargetNode);
                            Navigator.pop(ctx);
                            _showSnackBar('🧹 $report');
                            _loadAllData();
                          } catch (e) {
                            setDlgState(() => isPruning = false);
                            _showSnackBar('❌ Failed to prune volumes: $e', isError: true);
                          }
                        },
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showComposeSnippetDialog(StorageVolumeModel v) {
    final snippet = '''# Docker Compose Blueprint for Volume: ${v.name}
# Centurion Residency: ${v.nodeHostname.isNotEmpty ? v.nodeHostname : v.nodeId} (${v.nodeIp.isNotEmpty ? v.nodeIp : "Cluster"})

services:
  app_service:
    image: nginx:alpine
    volumes:
      - ${v.name}:/app/data

volumes:
  ${v.name}:
    external: true
''';

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.code, color: Color(0xFF38BDF8)),
              const SizedBox(width: 8),
              Text('Compose Snippet: ${v.name}'),
            ],
          ),
          content: SizedBox(
            width: 540,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Copy this YAML definition into your stack docker-compose.yml to bind this volume to any container service:',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: SelectableText(
                    snippet,
                    style: const TextStyle(
                      fontFamily: 'Courier New',
                      fontSize: 12.5,
                      color: Color(0xFF38BDF8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            OutlinedButton.icon(
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy Snippet'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: snippet));
                Navigator.pop(ctx);
                _showSnackBar('📋 Docker Compose snippet copied to clipboard');
              },
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _showInspectDockerVolumeDialog(StorageVolumeModel v) {
    showDialog(
      context: context,
      builder: (ctx) {
        return FutureBuilder<Map<String, dynamic>>(
          future: ApiService.inspectDockerVolume(name: v.name, targetNode: v.nodeId),
          builder: (context, snapshot) {
            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.info_outline, color: Color(0xFF38BDF8)),
                  const SizedBox(width: 8),
                  Text('Inspect Volume: ${v.name}'),
                ],
              ),
              content: SizedBox(
                width: 560,
                height: 380,
                child: snapshot.connectionState == ConnectionState.waiting
                    ? const Center(child: CircularProgressIndicator())
                    : snapshot.hasError
                        ? Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.redAccent)))
                        : SingleChildScrollView(
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F172A),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFF334155)),
                              ),
                              child: SelectableText(
                                JsonEncoder.withIndent('  ').convert(snapshot.data ?? {}),
                                style: const TextStyle(
                                  fontFamily: 'Courier New',
                                  fontSize: 12,
                                  color: Color(0xFF38BDF8),
                                ),
                              ),
                            ),
                          ),
              ),
              actions: [
                if (snapshot.hasData)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy JSON'),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(
                        text: JsonEncoder.withIndent('  ').convert(snapshot.data ?? {}),
                      ));
                      _showSnackBar('📋 Volume inspection copied to clipboard');
                    },
                  ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _deleteDockerVolumeConfirm(StorageVolumeModel v) {
    showDialog(
      context: context,
      builder: (ctx) {
        bool isDeleting = false;
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.delete_forever, color: Colors.redAccent),
                  SizedBox(width: 8),
                  Text('Delete Docker Volume'),
                ],
              ),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Are you sure you want to permanently delete Docker volume "${v.name}"?'),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('• Host: ${v.nodeHostname.isNotEmpty ? v.nodeHostname : v.nodeId} (${v.nodeIp})', style: const TextStyle(fontSize: 12)),
                          Text('• Mountpoint: ${v.sourcePath}', style: const TextStyle(fontSize: 12)),
                          Text('• Size: ${v.sizeFormatted}', style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                  icon: isDeleting
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.delete, size: 16),
                  label: const Text('Delete Volume'),
                  onPressed: isDeleting
                      ? null
                      : () async {
                          setDlgState(() => isDeleting = true);
                          try {
                            final msg = await ApiService.deleteDockerVolume(name: v.name, targetNode: v.nodeId);
                            Navigator.pop(ctx);
                            _showSnackBar('🗑️ $msg');
                            _loadAllData();
                          } catch (e) {
                            setDlgState(() => isDeleting = false);
                            _showSnackBar('❌ Failed to delete volume: $e', isError: true);
                          }
                        },
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showCreateBackupDialog({String? initialStackId, String? initialVolumeName, String? initialSourcePath}) {
    final nameCtrl = TextEditingController(text: initialVolumeName != null ? 'backup-$initialVolumeName' : '');
    final sourcePathCtrl = TextEditingController(text: initialSourcePath ?? '');
    final destinationPathCtrl = TextEditingController(text: '/var/backups/gbnt');
    String selectedStack = initialStackId ?? (widget.state.stacks.isNotEmpty ? widget.state.stacks.first.id : '');
    String selectedVolumeName = initialVolumeName ?? '';
    String sourceMode = (initialSourcePath != null || initialVolumeName != null) ? 'select' : (_volumes.isNotEmpty ? 'select' : 'custom');
    bool pauseContainer = true;
    bool isCreatingSourceDir = false;
    bool isCreatingDestDir = false;

    // Collect all selectable storage targets
    final List<Map<String, String>> selectableTargets = [];

    // 1. Volumes & Shared Pools
    for (final v in _volumes) {
      final label = v.type == 'docker_named'
          ? '💾 [Docker] ${v.name} (${v.nodeHostname})'
          : (v.type == 'shared_pool'
              ? '📁 [Shared] ${v.name} (/var/contenedores)'
              : '📂 [Bind] ${v.name} (${v.sourcePath})');
      selectableTargets.add({
        'id': v.id,
        'name': v.name,
        'path': v.sourcePath,
        'stackId': v.stackId,
        'label': label,
      });
    }

    // 2. Network Mounts
    for (final m in _mounts) {
      selectableTargets.add({
        'id': m.id,
        'name': m.name,
        'path': m.mountPoint,
        'stackId': '',
        'label': '🌐 [Mount] ${m.name} (${m.mountPoint})',
      });
    }

    // 3. Stacks
    for (final s in widget.state.stacks) {
      selectableTargets.add({
        'id': s.id,
        'name': s.name,
        'path': '/var/contenedores/${s.name}',
        'stackId': s.id,
        'label': '📦 [Stack] ${s.name} (${s.id})',
      });
    }

    String? selectedTargetId;
    if (initialVolumeName != null && initialVolumeName.isNotEmpty) {
      for (final t in selectableTargets) {
        if (t['name'] == initialVolumeName || t['path'] == initialSourcePath) {
          selectedTargetId = t['id'];
          break;
        }
      }
    } else if (selectableTargets.isNotEmpty) {
      selectedTargetId = selectableTargets.first['id'];
      if (sourcePathCtrl.text.isEmpty) {
        sourcePathCtrl.text = selectableTargets.first['path'] ?? '';
        selectedVolumeName = selectableTargets.first['name'] ?? '';
      }
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;

            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.archive, color: Color(0xFF10B981)),
                  SizedBox(width: 8),
                  Text('Create Compressed Backup / Snapshot'),
                ],
              ),
              content: SizedBox(
                width: 620,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Create a point-in-time compressed .tar.gz archive with cryptographic SHA-256 integrity verification.',
                        style: TextStyle(fontSize: 12.5, color: Colors.grey),
                      ),
                      const SizedBox(height: 16),

                      // 1. NOMBRE DEL BACKUP
                      _buildSectionHeader('1. NOMBRE DEL BACKUP / SNAPSHOT', Icons.label_outline, const Color(0xFF10B981), isDark),
                      const SizedBox(height: 8),
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Backup Name',
                          hintText: 'e.g. backup-wordpress-db',
                          prefixIcon: Icon(Icons.label_outline),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 2. ORIGEN DE DATOS
                      _buildSectionHeader('2. ORIGEN DE DATOS (¿Qué respaldar?)', Icons.source_outlined, const Color(0xFF38BDF8), isDark),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: 'select',
                              icon: Icon(Icons.inventory_2_outlined, size: 16),
                              label: Text('Discovered Volumes / Stacks'),
                            ),
                            ButtonSegment(
                              value: 'custom',
                              icon: Icon(Icons.folder_open, size: 16),
                              label: Text('Custom Filesystem Path'),
                            ),
                          ],
                          selected: {sourceMode},
                          onSelectionChanged: (newVal) {
                            setDlgState(() {
                              sourceMode = newVal.first;
                              if (sourceMode == 'select' && selectedTargetId != null) {
                                final match = selectableTargets.firstWhere(
                                  (t) => t['id'] == selectedTargetId,
                                  orElse: () => selectableTargets.first,
                                );
                                sourcePathCtrl.text = match['path'] ?? '';
                                selectedVolumeName = match['name'] ?? '';
                                if (match['stackId'] != null && match['stackId']!.isNotEmpty) {
                                  selectedStack = match['stackId']!;
                                }
                              }
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: 10),

                      if (sourceMode == 'select' && selectableTargets.isNotEmpty) ...[
                        DropdownButtonFormField<String>(
                          value: selectedTargetId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Select Discovered Volume, Pool or Stack',
                            prefixIcon: Icon(Icons.storage),
                            border: OutlineInputBorder(),
                          ),
                          items: selectableTargets.map((t) {
                            return DropdownMenuItem(
                              value: t['id'],
                              child: Text(
                                t['label'] ?? '',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setDlgState(() {
                                selectedTargetId = val;
                                final match = selectableTargets.firstWhere((t) => t['id'] == val);
                                sourcePathCtrl.text = match['path'] ?? '';
                                selectedVolumeName = match['name'] ?? '';
                                if (match['stackId'] != null && match['stackId']!.isNotEmpty) {
                                  selectedStack = match['stackId']!;
                                }
                                if (nameCtrl.text.isEmpty || nameCtrl.text.startsWith('backup-')) {
                                  nameCtrl.text = 'backup-${match['name']}';
                                }
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.folder_open, size: 16, color: Color(0xFF38BDF8)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Source Path: ${sourcePathCtrl.text}',
                                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: sourcePathCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Source Directory / Volume Path',
                                  hintText: 'e.g. /var/contenedores/wordpress/data or /data/storage',
                                  prefixIcon: Icon(Icons.folder_outlined),
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.explore, size: 16),
                              label: const Text('Browse...'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                              ),
                              onPressed: () async {
                                final selected = await _showDirectoryPickerDialog(
                                  initialPath: sourcePathCtrl.text.isNotEmpty ? sourcePathCtrl.text : '/var/contenedores',
                                  title: 'Browse Source Directory',
                                );
                                if (selected != null) {
                                  setDlgState(() {
                                    sourcePathCtrl.text = selected;
                                    if (nameCtrl.text.isEmpty || nameCtrl.text.startsWith('backup-')) {
                                      final baseName = selected.split('/').where((s) => s.isNotEmpty).lastOrNull ?? 'source';
                                      nameCtrl.text = 'backup-$baseName';
                                    }
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          children: [
                            ActionChip(
                              label: const Text('/var/contenedores/', style: TextStyle(fontSize: 11)),
                              onPressed: () => setDlgState(() => sourcePathCtrl.text = '/var/contenedores/'),
                            ),
                            ActionChip(
                              label: const Text('/var/lib/docker/volumes/', style: TextStyle(fontSize: 11)),
                              onPressed: () => setDlgState(() => sourcePathCtrl.text = '/var/lib/docker/volumes/'),
                            ),
                            ActionChip(
                              label: const Text('/mnt/shared/', style: TextStyle(fontSize: 11)),
                              onPressed: () => setDlgState(() => sourcePathCtrl.text = '/mnt/shared/'),
                            ),
                            ActionChip(
                              label: const Text('/data/', style: TextStyle(fontSize: 11)),
                              onPressed: () => setDlgState(() => sourcePathCtrl.text = '/data/'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            OutlinedButton.icon(
                              icon: isCreatingSourceDir
                                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.create_new_folder, size: 15, color: Color(0xFF38BDF8)),
                              label: const Text('Create Source Directory (mkdir -p)', style: TextStyle(fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                foregroundColor: const Color(0xFF38BDF8),
                              ),
                              onPressed: isCreatingSourceDir
                                  ? null
                                  : () async {
                                      final path = sourcePathCtrl.text.trim();
                                      if (path.isEmpty) {
                                        _showSnackBar('Please enter a source directory path first', isError: true);
                                        return;
                                      }
                                      setDlgState(() => isCreatingSourceDir = true);
                                      try {
                                        final ok = await ApiService.createStorageDirectory(
                                          path: path,
                                          targetNode: 'all',
                                          permissions: '0777',
                                        );
                                        if (ok) {
                                          _showSnackBar('✅ Source directory "$path" ready across cluster!');
                                          _loadAllData();
                                        } else {
                                          _showSnackBar('❌ Failed to create directory', isError: true);
                                        }
                                      } catch (e) {
                                        _showSnackBar('❌ Error: $e', isError: true);
                                      } finally {
                                        setDlgState(() => isCreatingSourceDir = false);
                                      }
                                    },
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 16),

                      // 3. DESTINO DEL BACKUP
                      _buildSectionHeader('3. DESTINO DEL BACKUP (¿Dónde guardar la copia?)', Icons.save_alt, const Color(0xFFF59E0B), isDark),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: destinationPathCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Destination Directory Path',
                                hintText: 'e.g. /var/backups/gbnt or /var/contenedores/backups',
                                prefixIcon: Icon(Icons.folder_special_outlined),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.explore, size: 16),
                            label: const Text('Browse...'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                            ),
                            onPressed: () async {
                              final selected = await _showDirectoryPickerDialog(
                                initialPath: destinationPathCtrl.text.isNotEmpty ? destinationPathCtrl.text : '/var/backups',
                                title: 'Browse / Select Destination Directory',
                              );
                              if (selected != null) {
                                setDlgState(() => destinationPathCtrl.text = selected);
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        children: [
                          ActionChip(
                            label: const Text('Default (/var/backups/gbnt)', style: TextStyle(fontSize: 11)),
                            onPressed: () => setDlgState(() => destinationPathCtrl.text = '/var/backups/gbnt'),
                          ),
                          ActionChip(
                            label: const Text('/var/contenedores/backups/', style: TextStyle(fontSize: 11)),
                            onPressed: () => setDlgState(() => destinationPathCtrl.text = '/var/contenedores/backups/'),
                          ),
                          ActionChip(
                            label: const Text('/data/backups/', style: TextStyle(fontSize: 11)),
                            onPressed: () => setDlgState(() => destinationPathCtrl.text = '/data/backups/'),
                          ),
                          ActionChip(
                            label: const Text('/mnt/shared/backups/', style: TextStyle(fontSize: 11)),
                            onPressed: () => setDlgState(() => destinationPathCtrl.text = '/mnt/shared/backups/'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            icon: isCreatingDestDir
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.create_new_folder, size: 15, color: Color(0xFFF59E0B)),
                            label: const Text('Create Destination Directory (mkdir -p)', style: TextStyle(fontSize: 12)),
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              foregroundColor: const Color(0xFFF59E0B),
                            ),
                            onPressed: isCreatingDestDir
                                ? null
                                : () async {
                                    final path = destinationPathCtrl.text.trim();
                                    if (path.isEmpty) {
                                      _showSnackBar('Please enter a destination path first', isError: true);
                                      return;
                                    }
                                    setDlgState(() => isCreatingDestDir = true);
                                    try {
                                      final ok = await ApiService.createStorageDirectory(
                                        path: path,
                                        targetNode: 'all',
                                        permissions: '0777',
                                      );
                                      if (ok) {
                                        _showSnackBar('✅ Destination directory "$path" ready across cluster!');
                                        _loadAllData();
                                      } else {
                                        _showSnackBar('❌ Failed to create directory', isError: true);
                                      }
                                    } catch (e) {
                                      _showSnackBar('❌ Error: $e', isError: true);
                                    } finally {
                                      setDlgState(() => isCreatingDestDir = false);
                                    }
                                  },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.auto_awesome, size: 16, color: Color(0xFF10B981)),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Auto-creación inteligente: La carpeta de destino (ej. /var/backups/gbnt) se creará automáticamente en el sistema con permisos 0777 al guardar el backup si aún no existe.',
                                style: TextStyle(fontSize: 11.5, color: Color(0xFF10B981), fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 4. OPCIONES
                      _buildSectionHeader('4. OPCIONES ADICIONALES', Icons.tune, Colors.grey, isDark),
                      const SizedBox(height: 8),
                      if (widget.state.stacks.isNotEmpty) ...[
                        DropdownButtonFormField<String>(
                          value: selectedStack.isNotEmpty ? selectedStack : null,
                          decoration: const InputDecoration(
                            labelText: 'Associated Stack (Legion) - Optional',
                            prefixIcon: Icon(Icons.layers_outlined),
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem(value: '', child: Text('None / Standalone Volume')),
                            ...widget.state.stacks.map((s) {
                              return DropdownMenuItem(
                                value: s.id,
                                child: Text('${s.name} (${s.id})'),
                              );
                            }),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setDlgState(() => selectedStack = val);
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                      ],

                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.lock_clock, size: 20, color: Color(0xFF10B981)),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Pause Containers during backup', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                                  Text('Freezes write operations temporarily for 100% DB consistency', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                ],
                              ),
                            ),
                            Switch(
                              value: pauseContainer,
                              activeColor: const Color(0xFF10B981),
                              onChanged: (val) => setDlgState(() => pauseContainer = val),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                FilledButton.icon(
                  icon: const Icon(Icons.archive, size: 18),
                  label: const Text('Create Backup'),
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    final srcPath = sourcePathCtrl.text.trim();
                    final destPath = destinationPathCtrl.text.trim();
                    if (name.isEmpty && srcPath.isEmpty) {
                      _showSnackBar('Please specify a backup name or source path', isError: true);
                      return;
                    }
                    Navigator.pop(ctx);
                    try {
                      _showSnackBar('Creating backup archive...');
                      await ApiService.createBackup(
                        name: name,
                        stackId: selectedStack,
                        volumeName: selectedVolumeName,
                        sourcePath: srcPath,
                        destinationPath: destPath,
                        pauseContainers: pauseContainer,
                      );
                      _showSnackBar('✅ Backup created successfully!');
                      _loadAllData();
                    } catch (e) {
                      _showSnackBar('❌ Failed to create backup: $e', isError: true);
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color, bool isDark) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12.5,
            color: color,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }

  void _showRestoreDialog(BackupModel backup) {
    final targetCtrl = TextEditingController(text: backup.sourcePath);
    bool isCreatingTarget = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.restore, color: Color(0xFF3B82F6)),
                  SizedBox(width: 8),
                  Text('Restore Backup Archive'),
                ],
              ),
              content: SizedBox(
                width: 540,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('You are about to restore backup "${backup.name}" (${backup.sizeFormatted}).', style: const TextStyle(fontSize: 13)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: targetCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Target Restore Directory',
                              hintText: 'e.g. /var/contenedores/wordpress/data',
                              prefixIcon: Icon(Icons.folder_outlined),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.explore, size: 16),
                          label: const Text('Browse...'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                          ),
                          onPressed: () async {
                            final selected = await _showDirectoryPickerDialog(
                              initialPath: targetCtrl.text.isNotEmpty ? targetCtrl.text : '/var/contenedores',
                              title: 'Select Restore Target Directory',
                            );
                            if (selected != null) {
                              setDlgState(() => targetCtrl.text = selected);
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      children: [
                        if (backup.sourcePath.isNotEmpty)
                          ActionChip(
                            label: const Text('Original Path', style: TextStyle(fontSize: 11)),
                            onPressed: () => setDlgState(() => targetCtrl.text = backup.sourcePath),
                          ),
                        ActionChip(
                          label: const Text('/var/contenedores/', style: TextStyle(fontSize: 11)),
                          onPressed: () => setDlgState(() => targetCtrl.text = '/var/contenedores/'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          icon: isCreatingTarget
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.create_new_folder, size: 16, color: Color(0xFF3B82F6)),
                          label: const Text('Ensure Target Directory Exists (mkdir -p)', style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            foregroundColor: const Color(0xFF3B82F6),
                          ),
                          onPressed: isCreatingTarget
                              ? null
                              : () async {
                                  final path = targetCtrl.text.trim();
                                  if (path.isEmpty) {
                                    _showSnackBar('Please enter a target path first', isError: true);
                                    return;
                                  }
                                  setDlgState(() => isCreatingTarget = true);
                                  try {
                                    final ok = await ApiService.createStorageDirectory(
                                      path: path,
                                      targetNode: 'all',
                                      permissions: '0777',
                                    );
                                    if (ok) {
                                      _showSnackBar('✅ Directory "$path" ready on host(s)!');
                                      _loadAllData();
                                    } else {
                                      _showSnackBar('❌ Failed to create directory', isError: true);
                                    }
                                  } catch (e) {
                                    _showSnackBar('❌ Error: $e', isError: true);
                                  } finally {
                                    setDlgState(() => isCreatingTarget = false);
                                  }
                                },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '⚠️ Existing files with the same name in the target directory will be overwritten with backup contents.',
                      style: TextStyle(fontSize: 11.5, color: Colors.orange),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                FilledButton.icon(
                  icon: const Icon(Icons.unarchive, size: 18),
                  label: const Text('Restore Now'),
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF3B82F6)),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    try {
                      _showSnackBar('Restoring backup archive...');
                      await ApiService.restoreBackup(
                        backupId: backup.id,
                        targetPath: targetCtrl.text.trim(),
                      );
                      _showSnackBar('✅ Backup restored successfully!');
                      _loadAllData();
                    } catch (e) {
                      _showSnackBar('❌ Failed to restore backup: $e', isError: true);
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showScheduleDialog({BackupScheduleModel? schedule}) {
    final nameCtrl = TextEditingController(text: schedule?.name ?? '');
    final cronCtrl = TextEditingController(text: schedule?.cronExpression ?? '0 3 * * *');
    final customPathCtrl = TextEditingController(
      text: schedule != null && (schedule.targetType == 'path' || schedule.targetId.startsWith('/'))
          ? schedule.targetId
          : '',
    );
    final destinationPathCtrl = TextEditingController(
      text: schedule?.destinationPath != null && schedule!.destinationPath.isNotEmpty
          ? schedule.destinationPath
          : '/var/backups/gbnt',
    );
    String targetType = schedule?.targetType ?? 'stack';
    String selectedStack = (schedule != null && schedule.targetType == 'stack')
        ? schedule.targetId
        : (widget.state.stacks.isNotEmpty ? widget.state.stacks.first.id : '');
    String selectedVolumeId = (schedule != null && schedule.targetType == 'volume')
        ? schedule.targetId
        : (_volumes.isNotEmpty ? _volumes.first.id : (_mounts.isNotEmpty ? _mounts.first.id : ''));
    int retention = schedule?.retentionCount ?? 7;
    bool pauseContainers = schedule?.pauseContainers ?? true;
    bool isCreatingSourceDir = false;
    bool isCreatingDestDir = false;

    // Collect selectable volumes and mounts
    final List<Map<String, String>> selectableVolumes = [];
    for (final v in _volumes) {
      final label = v.type == 'docker_named'
          ? '💾 [Docker] ${v.name} (${v.nodeHostname})'
          : (v.type == 'shared_pool'
              ? '📁 [Shared] ${v.name} (/var/contenedores)'
              : '📂 [Bind] ${v.name} (${v.sourcePath})');
      selectableVolumes.add({
        'id': v.id,
        'name': v.name,
        'path': v.sourcePath,
        'label': label,
      });
    }
    for (final m in _mounts) {
      selectableVolumes.add({
        'id': m.id,
        'name': m.name,
        'path': m.mountPoint,
        'label': '🌐 [Mount] ${m.name} (${m.mountPoint})',
      });
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;

            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.schedule, color: Color(0xFF8B5CF6)),
                  const SizedBox(width: 8),
                  Text(schedule == null ? 'New Backup Schedule' : 'Edit Backup Schedule'),
                ],
              ),
              content: SizedBox(
                width: 620,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. NOMBRE DE LA POLÍTICA
                      _buildSectionHeader('1. NOMBRE DE LA POLÍTICA', Icons.label_outline, const Color(0xFF8B5CF6), isDark),
                      const SizedBox(height: 8),
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Policy Name',
                          hintText: 'e.g. Daily WordPress DB Backup',
                          prefixIcon: Icon(Icons.label_outline),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 2. ORIGEN DE DATOS
                      _buildSectionHeader('2. ORIGEN DE DATOS (Target to Backup)', Icons.source_outlined, const Color(0xFF38BDF8), isDark),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: 'stack',
                              icon: Icon(Icons.layers_outlined, size: 16),
                              label: Text('Stack (Legion)'),
                            ),
                            ButtonSegment(
                              value: 'volume',
                              icon: Icon(Icons.inventory_2_outlined, size: 16),
                              label: Text('Volume / Mount'),
                            ),
                            ButtonSegment(
                              value: 'path',
                              icon: Icon(Icons.folder_outlined, size: 16),
                              label: Text('Custom Path'),
                            ),
                          ],
                          selected: {targetType},
                          onSelectionChanged: (newVal) {
                            setDlgState(() => targetType = newVal.first);
                          },
                        ),
                      ),
                      const SizedBox(height: 10),

                      if (targetType == 'stack') ...[
                        if (widget.state.stacks.isNotEmpty)
                          DropdownButtonFormField<String>(
                            value: selectedStack.isNotEmpty ? selectedStack : null,
                            decoration: const InputDecoration(
                              labelText: 'Target Stack (Legion)',
                              prefixIcon: Icon(Icons.layers_outlined),
                              border: OutlineInputBorder(),
                            ),
                            items: widget.state.stacks.map((s) {
                              return DropdownMenuItem(
                                value: s.id,
                                child: Text('${s.name} (${s.id})'),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setDlgState(() {
                                  selectedStack = val;
                                  if (nameCtrl.text.isEmpty || nameCtrl.text.startsWith('Daily ') || nameCtrl.text.startsWith('Backup ')) {
                                    final stack = widget.state.stacks.firstWhere((s) => s.id == val);
                                    nameCtrl.text = 'Daily ${stack.name} Backup';
                                  }
                                });
                              }
                            },
                          )
                        else
                          const Text('No stacks deployed yet.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ] else if (targetType == 'volume') ...[
                        if (selectableVolumes.isNotEmpty)
                          DropdownButtonFormField<String>(
                            value: selectedVolumeId.isNotEmpty ? selectedVolumeId : selectableVolumes.first['id'],
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Select Discovered Volume or Mount',
                              prefixIcon: Icon(Icons.inventory_2_outlined),
                              border: OutlineInputBorder(),
                            ),
                            items: selectableVolumes.map((v) {
                              return DropdownMenuItem(
                                value: v['id'],
                                child: Text(
                                  v['label'] ?? '',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setDlgState(() {
                                  selectedVolumeId = val;
                                  final match = selectableVolumes.firstWhere((v) => v['id'] == val);
                                  if (nameCtrl.text.isEmpty || nameCtrl.text.startsWith('Daily ') || nameCtrl.text.startsWith('Backup ')) {
                                    nameCtrl.text = 'Daily ${match['name']} Snapshot';
                                  }
                                });
                              }
                            },
                          )
                        else
                          const Text('No volumes or mounts discovered yet.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ] else ...[
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: customPathCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Directory Path',
                                  hintText: 'e.g. /var/contenedores/myapp or /data/glusterfs',
                                  prefixIcon: Icon(Icons.folder_outlined),
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.explore, size: 16),
                              label: const Text('Browse...'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                              ),
                              onPressed: () async {
                                final selected = await _showDirectoryPickerDialog(
                                  initialPath: customPathCtrl.text.isNotEmpty ? customPathCtrl.text : '/var/contenedores',
                                  title: 'Select Target Source Directory',
                                );
                                if (selected != null) {
                                  setDlgState(() => customPathCtrl.text = selected);
                                }
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          children: [
                            ActionChip(
                              label: const Text('/var/contenedores/', style: TextStyle(fontSize: 11)),
                              onPressed: () => setDlgState(() => customPathCtrl.text = '/var/contenedores/'),
                            ),
                            ActionChip(
                              label: const Text('/var/lib/docker/volumes/', style: TextStyle(fontSize: 11)),
                              onPressed: () => setDlgState(() => customPathCtrl.text = '/var/lib/docker/volumes/'),
                            ),
                            ActionChip(
                              label: const Text('/mnt/shared/', style: TextStyle(fontSize: 11)),
                              onPressed: () => setDlgState(() => customPathCtrl.text = '/mnt/shared/'),
                            ),
                            ActionChip(
                              label: const Text('/data/', style: TextStyle(fontSize: 11)),
                              onPressed: () => setDlgState(() => customPathCtrl.text = '/data/'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            OutlinedButton.icon(
                              icon: isCreatingSourceDir
                                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.create_new_folder, size: 16, color: Color(0xFF8B5CF6)),
                              label: const Text('Create Directory on Host(s) (mkdir -p)', style: TextStyle(fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                foregroundColor: const Color(0xFF8B5CF6),
                              ),
                              onPressed: isCreatingSourceDir
                                  ? null
                                  : () async {
                                      final path = customPathCtrl.text.trim();
                                      if (path.isEmpty) {
                                        _showSnackBar('Please enter a directory path first', isError: true);
                                        return;
                                      }
                                      setDlgState(() => isCreatingSourceDir = true);
                                      try {
                                        final ok = await ApiService.createStorageDirectory(
                                          path: path,
                                          targetNode: 'all',
                                          permissions: '0777',
                                        );
                                        if (ok) {
                                          _showSnackBar('✅ Directory "$path" created across cluster!');
                                          _loadAllData();
                                        } else {
                                          _showSnackBar('❌ Failed to create directory', isError: true);
                                        }
                                      } catch (e) {
                                        _showSnackBar('❌ Error: $e', isError: true);
                                      } finally {
                                        setDlgState(() => isCreatingSourceDir = false);
                                      }
                                    },
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 16),

                      // 3. DESTINO DEL BACKUP
                      _buildSectionHeader('3. DESTINO DEL BACKUP (¿Dónde guardar las copias?)', Icons.save_alt, const Color(0xFFF59E0B), isDark),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: destinationPathCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Destination Directory Path',
                                hintText: 'e.g. /var/backups/gbnt or /var/contenedores/backups',
                                prefixIcon: Icon(Icons.folder_special_outlined),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.explore, size: 16),
                            label: const Text('Browse...'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                            ),
                            onPressed: () async {
                              final selected = await _showDirectoryPickerDialog(
                                initialPath: destinationPathCtrl.text.isNotEmpty ? destinationPathCtrl.text : '/var/backups',
                                title: 'Select Backup Destination Directory',
                              );
                              if (selected != null) {
                                setDlgState(() => destinationPathCtrl.text = selected);
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        children: [
                          ActionChip(
                            label: const Text('Default (/var/backups/gbnt)', style: TextStyle(fontSize: 11)),
                            onPressed: () => setDlgState(() => destinationPathCtrl.text = '/var/backups/gbnt'),
                          ),
                          ActionChip(
                            label: const Text('/var/contenedores/backups/', style: TextStyle(fontSize: 11)),
                            onPressed: () => setDlgState(() => destinationPathCtrl.text = '/var/contenedores/backups/'),
                          ),
                          ActionChip(
                            label: const Text('/data/backups/', style: TextStyle(fontSize: 11)),
                            onPressed: () => setDlgState(() => destinationPathCtrl.text = '/data/backups/'),
                          ),
                          ActionChip(
                            label: const Text('/mnt/shared/backups/', style: TextStyle(fontSize: 11)),
                            onPressed: () => setDlgState(() => destinationPathCtrl.text = '/mnt/shared/backups/'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            icon: isCreatingDestDir
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.create_new_folder, size: 15, color: Color(0xFFF59E0B)),
                            label: const Text('Create Destination Directory (mkdir -p)', style: TextStyle(fontSize: 12)),
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              foregroundColor: const Color(0xFFF59E0B),
                            ),
                            onPressed: isCreatingDestDir
                                ? null
                                : () async {
                                    final path = destinationPathCtrl.text.trim();
                                    if (path.isEmpty) {
                                      _showSnackBar('Please enter a destination path first', isError: true);
                                      return;
                                    }
                                    setDlgState(() => isCreatingDestDir = true);
                                    try {
                                      final ok = await ApiService.createStorageDirectory(
                                        path: path,
                                        targetNode: 'all',
                                        permissions: '0777',
                                      );
                                      if (ok) {
                                        _showSnackBar('✅ Destination directory "$path" ready across cluster!');
                                        _loadAllData();
                                      } else {
                                        _showSnackBar('❌ Failed to create directory', isError: true);
                                      }
                                    } catch (e) {
                                      _showSnackBar('❌ Error: $e', isError: true);
                                    } finally {
                                      setDlgState(() => isCreatingDestDir = false);
                                    }
                                  },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.auto_awesome, size: 16, color: Color(0xFF10B981)),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Auto-creación inteligente: La carpeta de destino (ej. /var/backups/gbnt) se creará automáticamente en el sistema con permisos 0777 al ejecutar el snapshot programado si aún no existe.',
                                style: TextStyle(fontSize: 11.5, color: Color(0xFF10B981), fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 4. PROGRAMACIÓN & RETENCIÓN
                      _buildSectionHeader('4. PROGRAMACIÓN & RETENCIÓN', Icons.alarm_outlined, const Color(0xFF8B5CF6), isDark),
                      const SizedBox(height: 8),
                      TextField(
                        controller: cronCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Cron Expression',
                          hintText: 'e.g. 0 3 * * * (Daily at 03:00 AM)',
                          prefixIcon: Icon(Icons.alarm_outlined),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          ActionChip(
                            label: const Text('Daily (3 AM)', style: TextStyle(fontSize: 11)),
                            onPressed: () => setDlgState(() => cronCtrl.text = '0 3 * * *'),
                          ),
                          ActionChip(
                            label: const Text('Every 12h', style: TextStyle(fontSize: 11)),
                            onPressed: () => setDlgState(() => cronCtrl.text = '0 */12 * * *'),
                          ),
                          ActionChip(
                            label: const Text('Every 6h', style: TextStyle(fontSize: 11)),
                            onPressed: () => setDlgState(() => cronCtrl.text = '0 */6 * * *'),
                          ),
                          ActionChip(
                            label: const Text('Weekly (Sun)', style: TextStyle(fontSize: 11)),
                            onPressed: () => setDlgState(() => cronCtrl.text = '0 3 * * 0'),
                          ),
                          ActionChip(
                            label: const Text('Hourly', style: TextStyle(fontSize: 11)),
                            onPressed: () => setDlgState(() => cronCtrl.text = '0 * * * *'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Text('Retention (Keep Last N):', style: TextStyle(fontSize: 13)),
                          const Spacer(),
                          DropdownButton<int>(
                            value: retention,
                            items: [3, 7, 14, 30, 60].map((n) {
                              return DropdownMenuItem(value: n, child: Text('$n copies'));
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) setDlgState(() => retention = val);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Text('Pause Containers during backup:', style: TextStyle(fontSize: 13)),
                          const Spacer(),
                          Switch(
                            value: pauseContainers,
                            activeColor: const Color(0xFF8B5CF6),
                            onChanged: (val) => setDlgState(() => pauseContainers = val),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6)),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    try {
                      String targetId = '';
                      String targetName = '';

                      if (targetType == 'stack') {
                        targetId = selectedStack;
                        final match = widget.state.stacks.where((s) => s.id == selectedStack);
                        targetName = match.isNotEmpty ? match.first.name : selectedStack;
                      } else if (targetType == 'volume') {
                        targetId = selectedVolumeId;
                        final match = selectableVolumes.where((v) => v['id'] == selectedVolumeId);
                        if (match.isNotEmpty) {
                          targetName = match.first['name'] ?? selectedVolumeId;
                          if (match.first['path'] != null && match.first['path']!.isNotEmpty) {
                            targetId = match.first['path']!;
                          }
                        } else {
                          targetName = selectedVolumeId;
                        }
                      } else {
                        targetId = customPathCtrl.text.trim();
                        targetName = customPathCtrl.text.trim();
                      }

                      final item = BackupScheduleModel(
                        id: schedule?.id ?? '',
                        name: nameCtrl.text.trim().isNotEmpty ? nameCtrl.text.trim() : 'Scheduled Backup ($targetName)',
                        cronExpression: cronCtrl.text.trim(),
                        targetType: targetType,
                        targetId: targetId,
                        targetName: targetName,
                        destinationPath: destinationPathCtrl.text.trim(),
                        retentionCount: retention,
                        pauseContainers: pauseContainers,
                        enabled: schedule?.enabled ?? true,
                      );
                      await ApiService.saveBackupSchedule(item);
                      _showSnackBar('✅ Schedule saved successfully!');
                      _loadAllData();
                    } catch (e) {
                      _showSnackBar('❌ Failed to save schedule: $e', isError: true);
                    }
                  },
                  child: const Text('Save Policy'),
                ),
              ],
            );
          },
        );
      },
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
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.inventory_2, color: Color(0xFF10B981), size: 28),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Storage & Backups',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                          ),
                          child: const Text(
                            'THE GRANARIES',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF10B981), letterSpacing: 0.8),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Cluster persistent volumes, shared storage pools (/var/contenedores), snapshots, and backup policies',
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
            const SizedBox(height: 20),

            // Tab Bar
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                indicator: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: const Color(0xFF10B981),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF10B981).withValues(alpha: 0.35),
                      blurRadius: 6,
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
                    height: 44,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.inventory_2_outlined, size: 18),
                          const SizedBox(width: 8),
                          Text('Volumes (${_volumes.length})'),
                        ],
                      ),
                    ),
                  ),
                  Tab(
                    height: 44,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.backup_outlined, size: 18),
                          const SizedBox(width: 8),
                          Text('Backups & Snapshots (${_backups.length})'),
                        ],
                      ),
                    ),
                  ),
                  Tab(
                    height: 44,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.schedule_outlined, size: 18),
                          const SizedBox(width: 8),
                          Text('Schedules (${_schedules.length})'),
                        ],
                      ),
                    ),
                  ),
                  const Tab(
                    height: 44,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.folder_shared_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('Storage Pools'),
                        ],
                      ),
                    ),
                  ),
                  Tab(
                    height: 44,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.dns_outlined, size: 18),
                          const SizedBox(width: 8),
                          Text('Network Mounts & fstab (${_mounts.length})'),
                        ],
                      ),
                    ),
                  ),
                  Tab(
                    height: 44,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.hub_outlined, size: 18),
                          const SizedBox(width: 8),
                          Text('GlusterFS Cluster (${_glusterVolumes.length})'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Tab Content
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildVolumesTab(isDark),
                        _buildBackupsTab(isDark),
                        _buildSchedulesTab(isDark),
                        _buildPoolsTab(isDark),
                        _buildMountsTab(isDark),
                        _buildGlusterTab(isDark),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Tab 1: Volumes View ──────────────────────────────────────────

  Widget _buildVolumesTab(bool isDark) {
    final filtered = _volumes.where((v) {
      final matchesSearch = _volumeSearch.isEmpty ||
          v.name.toLowerCase().contains(_volumeSearch.toLowerCase()) ||
          v.stackName.toLowerCase().contains(_volumeSearch.toLowerCase()) ||
          v.sourcePath.toLowerCase().contains(_volumeSearch.toLowerCase()) ||
          v.nodeId.toLowerCase().contains(_volumeSearch.toLowerCase()) ||
          v.nodeHostname.toLowerCase().contains(_volumeSearch.toLowerCase()) ||
          v.nodeIp.toLowerCase().contains(_volumeSearch.toLowerCase());
      final matchesType = _volumeTypeFilter == 'ALL' || v.type == _volumeTypeFilter;
      final matchesNode = _volumeNodeFilter == 'ALL' ||
          v.nodeId == _volumeNodeFilter ||
          v.nodeIp == _volumeNodeFilter ||
          (v.nodeId == 'cluster' && _volumeNodeFilter == 'ALL');
      return matchesSearch && matchesType && matchesNode;
    }).toList();

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search volumes by name, host IP, stack, or path...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1E293B) : Colors.grey[100],
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                ),
                onChanged: (val) => setState(() => _volumeSearch = val),
              ),
            ),
            const SizedBox(width: 8),
            // Volume Type Dropdown
            DropdownButton<String>(
              value: _volumeTypeFilter,
              items: const [
                DropdownMenuItem(value: 'ALL', child: Text('All Types')),
                DropdownMenuItem(value: 'docker_named', child: Text('Docker Named Volumes')),
                DropdownMenuItem(value: 'shared_pool', child: Text('Shared Pool (/var/contenedores)')),
                DropdownMenuItem(value: 'host_bind', child: Text('Host Bind Mounts')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _volumeTypeFilter = val);
              },
            ),
            const SizedBox(width: 8),
            // Node Filter Dropdown
            DropdownButton<String>(
              value: _volumeNodeFilter,
              items: [
                const DropdownMenuItem(value: 'ALL', child: Text('🌐 All Centurions')),
                const DropdownMenuItem(value: 'node-local-manager', child: Text('👑 Manager (Local)')),
                ...widget.state.nodes.map(
                  (n) => DropdownMenuItem(
                    value: n.id,
                    child: Text('💻 ${n.role.toUpperCase()}: ${n.ip}'),
                  ),
                ),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() => _volumeNodeFilter = val);
                  _loadAllData();
                }
              },
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.cleaning_services_outlined, size: 16, color: Colors.orange),
              label: const Text('Prune Unused', style: TextStyle(color: Colors.orange)),
              onPressed: _showPruneDockerVolumesDialog,
            ),
            const SizedBox(width: 6),
            OutlinedButton.icon(
              icon: const Icon(Icons.folder_open, size: 16),
              label: const Text('Explore (ls)'),
              onPressed: () => _showDirectoryExplorerDialog('/var/contenedores', initialNode: _volumeNodeFilter),
            ),
            const SizedBox(width: 6),
            OutlinedButton.icon(
              icon: const Icon(Icons.create_new_folder, size: 16),
              label: const Text('New Dir'),
              onPressed: () => _showCreateDirectoryDialog(initialNode: _volumeNodeFilter),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
              icon: const Icon(Icons.add_box, size: 16),
              label: const Text('Create Docker Volume'),
              onPressed: () => _showCreateDockerVolumeDialog(initialNode: _volumeNodeFilter),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey[600]),
                      const SizedBox(height: 10),
                      Text(
                        'No volumes found matching the filter criteria.',
                        style: TextStyle(color: Colors.grey[400], fontSize: 14),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FilledButton.icon(
                            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                            icon: const Icon(Icons.add_box, size: 16),
                            label: const Text('Create Docker Volume'),
                            onPressed: () => _showCreateDockerVolumeDialog(initialNode: _volumeNodeFilter),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.create_new_folder, size: 16),
                            label: const Text('Create Storage Directory'),
                            onPressed: () => _showCreateDirectoryDialog(initialNode: _volumeNodeFilter),
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (ctx, i) {
                    final v = filtered[i];
                    final isDockerVol = v.type == 'docker_named';
                    final isManager = v.nodeRole == 'MANAGER' || v.nodeId == 'node-local-manager';
                    final isWorker = v.nodeRole == 'WORKER' || v.nodeId.startsWith('node-');

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
                                color: v.isShared
                                    ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                    : isDockerVol
                                        ? Colors.blue.withValues(alpha: 0.15)
                                        : Colors.grey.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                v.isShared
                                    ? Icons.cloud_done
                                    : isDockerVol
                                        ? Icons.dns
                                        : Icons.storage,
                                color: v.isShared
                                    ? const Color(0xFF10B981)
                                    : isDockerVol
                                        ? Colors.lightBlueAccent
                                        : Colors.grey,
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
                                      Text(v.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                      const SizedBox(width: 8),
                                      // Centurion Host Chip
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: isManager
                                              ? Colors.purple.withValues(alpha: 0.2)
                                              : isWorker
                                                  ? Colors.cyan.withValues(alpha: 0.2)
                                                  : const Color(0xFF10B981).withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(
                                            color: isManager
                                                ? Colors.purpleAccent.withValues(alpha: 0.4)
                                                : isWorker
                                                    ? Colors.cyanAccent.withValues(alpha: 0.4)
                                                    : const Color(0xFF10B981).withValues(alpha: 0.4),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              isManager
                                                  ? Icons.military_tech
                                                  : isWorker
                                                      ? Icons.computer
                                                      : Icons.hub,
                                              size: 13,
                                              color: isManager
                                                  ? Colors.purpleAccent
                                                  : isWorker
                                                      ? Colors.cyanAccent
                                                      : const Color(0xFF10B981),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              isManager
                                                  ? '👑 MANAGER: ${v.nodeHostname.isNotEmpty ? v.nodeHostname : "Local"} (${v.nodeIp.isNotEmpty ? v.nodeIp : "127.0.0.1"})'
                                                  : isWorker
                                                      ? '💻 CENTURION: ${v.nodeHostname.isNotEmpty ? v.nodeHostname : v.nodeId} (${v.nodeIp})'
                                                      : '🌐 ALL CENTURIONS (Shared)',
                                              style: TextStyle(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.bold,
                                                color: isManager
                                                    ? Colors.purpleAccent
                                                    : isWorker
                                                        ? Colors.cyanAccent
                                                        : const Color(0xFF10B981),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      // Type chip
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: v.isShared
                                              ? const Color(0xFF10B981).withValues(alpha: 0.2)
                                              : isDockerVol
                                                  ? Colors.blue.withValues(alpha: 0.2)
                                                  : Colors.grey.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          v.type.toUpperCase().replaceAll('_', ' '),
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.bold,
                                            color: v.isShared
                                                ? const Color(0xFF10B981)
                                                : isDockerVol
                                                    ? Colors.lightBlueAccent
                                                    : Colors.grey[400],
                                          ),
                                        ),
                                      ),
                                      if (v.driver.isNotEmpty) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.blueGrey.withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            'driver: ${v.driver}',
                                            style: TextStyle(fontSize: 9.5, color: isDark ? Colors.blueGrey[200] : Colors.blueGrey[800]),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Origin: ${v.stackName.isNotEmpty ? v.stackName : "System Volume"} | Source: ${v.sourcePath}${v.targetPath.isNotEmpty && v.targetPath != v.sourcePath ? " ➔ Target: ${v.targetPath}" : ""}',
                                    style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.purple.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                v.sizeFormatted,
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.purpleAccent, fontSize: 13),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.folder_open, size: 14),
                              label: const Text('Files (ls)'),
                              style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                              onPressed: () {
                                _showDirectoryExplorerDialog(
                                  v.sourcePath,
                                  initialNode: v.nodeId,
                                );
                              },
                            ),
                            const SizedBox(width: 6),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.code, size: 14, color: Color(0xFF38BDF8)),
                              label: const Text('Compose', style: TextStyle(color: Color(0xFF38BDF8))),
                              style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                              onPressed: () => _showComposeSnippetDialog(v),
                            ),
                            if (isDockerVol) ...[
                              const SizedBox(width: 6),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.info_outline, size: 14),
                                label: const Text('Inspect'),
                                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                                onPressed: () => _showInspectDockerVolumeDialog(v),
                              ),
                            ],
                            const SizedBox(width: 6),
                            FilledButton.icon(
                              icon: const Icon(Icons.camera_alt, size: 14),
                              label: const Text('Snapshot'),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () {
                                _showCreateBackupDialog(
                                  initialStackId: v.stackId,
                                  initialVolumeName: v.name,
                                  initialSourcePath: v.sourcePath,
                                );
                              },
                            ),
                            if (isDockerVol) ...[
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                                tooltip: 'Delete Docker Volume',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _deleteDockerVolumeConfirm(v),
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

  // ── Tab 2: Backups & Snapshots View ──────────────────────────────

  Widget _buildBackupsTab(bool isDark) {
    final filtered = _backups.where((b) {
      return _backupSearch.isEmpty ||
          b.name.toLowerCase().contains(_backupSearch.toLowerCase()) ||
          b.stackName.toLowerCase().contains(_backupSearch.toLowerCase()) ||
          b.sha256.toLowerCase().contains(_backupSearch.toLowerCase());
    }).toList();

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search backups by name, stack, or SHA-256 hash...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1E293B) : Colors.grey[100],
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                ),
                onChanged: (val) => setState(() => _backupSearch = val),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Create Backup'),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
              onPressed: () => _showCreateBackupDialog(),
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
                      Icon(Icons.backup_outlined, size: 48, color: Colors.grey[600]),
                      const SizedBox(height: 12),
                      const Text('No backups found. Create your first compressed snapshot!'),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (ctx, i) {
                    final b = filtered[i];
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
                                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.archive, color: Color(0xFF10B981), size: 24),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(b.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: b.isScheduled
                                              ? Colors.purple.withValues(alpha: 0.2)
                                              : Colors.blue.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          b.isScheduled ? 'SCHEDULED' : 'MANUAL',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: b.isScheduled ? Colors.purpleAccent : Colors.blueAccent,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Stack: ${b.stackName.isNotEmpty ? b.stackName : "All"} | Created: ${b.createdAt} | Path: ${b.filePath}',
                                    style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                                  ),
                                  const SizedBox(height: 4),
                                  InkWell(
                                    onTap: () {
                                      Clipboard.setData(ClipboardData(text: b.sha256));
                                      _showSnackBar('SHA-256 copied to clipboard');
                                    },
                                    child: Text(
                                      'SHA-256: ${b.sha256}',
                                      style: const TextStyle(fontFamily: 'Courier New', fontSize: 11, color: Colors.grey),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                b.sizeFormatted,
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF10B981), fontSize: 13),
                              ),
                            ),
                            const SizedBox(width: 12),
                            IconButton(
                              icon: const Icon(Icons.download, size: 20, color: Colors.blueAccent),
                              tooltip: 'Download .tar.gz',
                              onPressed: () => _downloadBackup(b.id, b.name),
                            ),
                            IconButton(
                              icon: const Icon(Icons.restore, size: 20, color: Color(0xFF10B981)),
                              tooltip: 'Restore Backup',
                              onPressed: () => _showRestoreDialog(b),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                              tooltip: 'Delete Backup',
                              onPressed: () => _deleteBackup(b.id, b.name),
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

  // ── Tab 3: Schedules View ────────────────────────────────────────

  Widget _buildSchedulesTab(bool isDark) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Automated Backup Routines & Retention Policies',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New Backup Schedule'),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6)),
              onPressed: () => _showScheduleDialog(),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Expanded(
          child: _schedules.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.schedule_outlined, size: 48, color: Colors.grey[600]),
                      const SizedBox(height: 12),
                      const Text('No automated backup schedules configured yet.'),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: _schedules.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (ctx, i) {
                    final s = _schedules[i];
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
                              child: const Icon(Icons.alarm, color: Color(0xFF8B5CF6), size: 24),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(s.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: s.enabled ? Colors.green.withValues(alpha: 0.2) : Colors.grey.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          s.enabled ? 'ACTIVE' : 'PAUSED',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: s.enabled ? Colors.greenAccent : Colors.grey,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Cron: ${s.cronExpression} | Target: ${s.targetName} | Retention: Last ${s.retentionCount} copies',
                                    style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit, size: 20, color: Colors.blueAccent),
                              tooltip: 'Edit Schedule',
                              onPressed: () => _showScheduleDialog(schedule: s),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                              tooltip: 'Delete Schedule',
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Delete Schedule'),
                                    content: Text('Delete backup schedule "${s.name}"?'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                      FilledButton(
                                        style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                                        onPressed: () => Navigator.pop(ctx, true),
                                        child: const Text('Delete'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  await ApiService.deleteBackupSchedule(s.id);
                                  _showSnackBar('Schedule deleted');
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

  // ── Tab 4: Storage Pools View ─────────────────────────────────────

  Widget _buildPoolsTab(bool isDark) {
    final health = _poolHealth;
    final isHealthy = health?.status == 'healthy';

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Base path card
          Card(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.folder_shared, color: Color(0xFF10B981), size: 24),
                      const SizedBox(width: 10),
                      const Text('Shared Storage Pool Configuration', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isHealthy ? const Color(0xFF10B981).withValues(alpha: 0.2) : Colors.orange.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isHealthy ? const Color(0xFF10B981) : Colors.orange),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(isHealthy ? Icons.check_circle : Icons.warning, size: 14, color: isHealthy ? const Color(0xFF10B981) : Colors.orange),
                            const SizedBox(width: 6),
                            Text(
                              isHealthy ? 'POOL HEALTHY (RW)' : 'DEGRADED / NOT MOUNTED',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isHealthy ? const Color(0xFF10B981) : Colors.orange,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Shared mount directory accessible across all nodes for container mobility: $_poolPath',
                    style: TextStyle(fontSize: 13, color: Colors.grey[400]),
                  ),
                  if (health != null && health.totalBytes > 0) ...[
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Disk Usage: ${health.usedFormatted} / ${health.totalFormatted} (${health.usagePercent.toStringAsFixed(1)}%)'),
                        Text('Free Space: ${health.freeFormatted}', style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: health.usagePercent / 100.0,
                        minHeight: 10,
                        backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.grey[300],
                        valueColor: AlwaysStoppedAnimation<Color>(
                          health.usagePercent > 85 ? Colors.redAccent : const Color(0xFF10B981),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Node Health Matrix
          const Text('Centurion Nodes Health Matrix', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 10),
          if (health?.nodes != null && health!.nodes.isNotEmpty) ...[
            ...health.nodes.map((n) {
              return Card(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: n.isWritable ? Colors.green.withValues(alpha: 0.15) : Colors.orange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          n.isWritable ? Icons.dns : Icons.error_outline,
                          color: n.isWritable ? Colors.greenAccent : Colors.orange,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text('${n.nodeId} (${n.nodeIp})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    n.role.toUpperCase(),
                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueAccent),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Mount: ${n.path} | Writable: ${n.isWritable ? "Yes (RW)" : "No (RO/Missing)"}',
                              style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                            ),
                            if (n.error != null && n.error!.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text('Error: ${n.error}', style: const TextStyle(fontSize: 11, color: Colors.redAccent)),
                            ],
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: n.isWritable ? Colors.green.withValues(alpha: 0.15) : Colors.orange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          n.status.toUpperCase(),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: n.isWritable ? Colors.greenAccent : Colors.orange,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],

          const SizedBox(height: 16),
          // NFS / Storage Mount Helper Card
          Card(
            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.lightbulb_outline, color: Color(0xFFF97316), size: 20),
                      SizedBox(width: 8),
                      Text('How to Configure Shared Storage (/var/contenedores)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'To allow containers to move between hosts without data loss, mount an NFS, GlusterFS, or CephFS share on /var/contenedores on all Manager and Worker nodes:',
                    style: TextStyle(fontSize: 12.5),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    'sudo mkdir -p /var/contenedores\nsudo mount -t nfs <NFS_SERVER_IP>:/storage/contenedores /var/contenedores',
                    style: TextStyle(
                      fontFamily: 'Courier New',
                      fontSize: 12,
                      color: isDark ? const Color(0xFFF97316) : Colors.deepOrange,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(
    bool isDark,
    String title,
    String value,
    String subtitle,
    IconData icon,
    Color color,
  ) {
    return Card(
      elevation: 0,
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: isDark ? const Color(0xFF334155) : Colors.grey[300]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Tab 5: Network Mounts & /etc/fstab ─────────────────────────────

  Widget _buildMountsTab(bool isDark) {
    final filtered = _mounts.where((m) {
      final matchesSearch = _mountSearch.isEmpty ||
          m.name.toLowerCase().contains(_mountSearch.toLowerCase()) ||
          m.device.toLowerCase().contains(_mountSearch.toLowerCase()) ||
          m.mountPoint.toLowerCase().contains(_mountSearch.toLowerCase()) ||
          m.description.toLowerCase().contains(_mountSearch.toLowerCase());
      final matchesType = _mountTypeFilter == 'ALL' ||
          m.fsType.toLowerCase().contains(_mountTypeFilter.toLowerCase());
      return matchesSearch && matchesType;
    }).toList();

    final mountedCount = _mounts.where((m) => m.status == 'mounted').length;
    final fstabCount = _mounts.where((m) => m.autoMount).length;
    final isMobilityActive = _mounts.any((m) => m.mountPoint == '/var/contenedores' && m.status == 'mounted');

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Metric Cards
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  isDark,
                  'Active Mounts',
                  '$mountedCount / ${_mounts.length}',
                  mountedCount > 0 ? '🟢 All connected' : '⚪ No active network shares',
                  Icons.dns_outlined,
                  const Color(0xFF3B82F6),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  isDark,
                  '/var/contenedores Mobility',
                  isMobilityActive ? 'SHARED NETWORK' : 'LOCAL ATTACHED',
                  isMobilityActive ? '🟢 Multi-node mobility active' : '🟡 Data bound to single host',
                  Icons.folder_special_outlined,
                  isMobilityActive ? const Color(0xFF10B981) : Colors.orange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  isDark,
                  '/etc/fstab Managed Entries',
                  '$fstabCount Entries',
                  'Persistence on reboot enabled',
                  Icons.save_outlined,
                  const Color(0xFF8B5CF6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Action & Filter Toolbar
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search mounts by device, path, or name...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onChanged: (val) => setState(() => _mountSearch = val),
                ),
              ),
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: _mountTypeFilter,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: 'ALL', child: Text('All Protocols')),
                  DropdownMenuItem(value: 'nfs', child: Text('NFS (v3/v4)')),
                  DropdownMenuItem(value: 'cifs', child: Text('Samba / CIFS')),
                  DropdownMenuItem(value: 's3', child: Text('S3 Object Storage')),
                  DropdownMenuItem(value: 'ext', child: Text('Local / POSIX')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _mountTypeFilter = val);
                },
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                tooltip: 'Refresh Mounts Data',
                onPressed: _loadAllData,
              ),
              const SizedBox(width: 4),
              OutlinedButton.icon(
                icon: const Icon(Icons.edit_note, size: 16),
                label: const Text('Edit /etc/fstab'),
                onPressed: _showFstabViewerDialog,
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.sync, size: 16),
                label: const Text('Mount All (mount -a)'),
                onPressed: _showMountAllDialog,
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Network Mount'),
                onPressed: () => _showAddMountDialog(),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Mounts Table
          if (filtered.isEmpty)
            Card(
              elevation: 0,
              color: isDark ? const Color(0xFF1E293B) : Colors.grey[100],
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.dns_outlined, size: 48, color: Colors.grey[500]),
                      const SizedBox(height: 12),
                      Text(
                        _mounts.isEmpty
                            ? 'No network mounts configured yet.'
                            : 'No mounts match your search filter.',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Mount remote NFS shares, Windows Samba folders, or S3 buckets to /var/contenedores for container data mobility.',
                        style: TextStyle(color: Colors.grey[400], fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Configure First Mount (NFS / S3 / Samba)'),
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                        onPressed: () => _showAddMountDialog(),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: isDark ? const Color(0xFF334155) : Colors.grey[300]!),
              ),
              clipBehavior: Clip.antiAlias,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC)),
                columnSpacing: 16,
                columns: const [
                  DataColumn(label: Text('PROTOCOL')),
                  DataColumn(label: Text('NAME & DESCRIPTION')),
                  DataColumn(label: Text('TARGET HOST')),
                  DataColumn(label: Text('REMOTE DEVICE / SHARE')),
                  DataColumn(label: Text('LOCAL MOUNT POINT')),
                  DataColumn(label: Text('AUTO-BOOT')),
                  DataColumn(label: Text('STATUS')),
                  DataColumn(label: Text('ACTIONS')),
                ],
                rows: filtered.map((m) {
                  Color typeColor = const Color(0xFF3B82F6);
                  String typeLabel = m.fsType.toUpperCase();
                  if (m.fsType.contains('cifs')) {
                    typeColor = const Color(0xFFF59E0B);
                    typeLabel = 'SAMBA / CIFS';
                  } else if (m.fsType.contains('s3')) {
                    typeColor = const Color(0xFF10B981);
                    typeLabel = 'S3 BUCKET';
                  } else if (m.fsType.contains('nfs')) {
                    typeColor = const Color(0xFF3B82F6);
                    typeLabel = 'NFS';
                  }

                  Color statusColor = Colors.orange;
                  if (m.status == 'mounted') {
                    statusColor = const Color(0xFF10B981);
                  } else if (m.status == 'error') {
                    statusColor = Colors.redAccent;
                  }

                  return DataRow(
                    cells: [
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: typeColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: typeColor.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            typeLabel,
                            style: TextStyle(color: typeColor, fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                        ),
                      ),
                      DataCell(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(m.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            if (m.description.isNotEmpty)
                              Text(m.description, style: TextStyle(fontSize: 11, color: Colors.grey[400])),
                          ],
                        ),
                      ),
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: m.targetNode == 'all'
                                ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                : (isDark ? Colors.grey[800] : Colors.grey[200]),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: m.targetNode == 'all'
                                  ? const Color(0xFF10B981).withValues(alpha: 0.3)
                                  : Colors.transparent,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                m.targetNode == 'all' ? Icons.public : Icons.computer,
                                size: 13,
                                color: m.targetNode == 'all' ? const Color(0xFF10B981) : (isDark ? Colors.grey[300] : Colors.grey[700]),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                m.targetNode == 'all'
                                    ? 'All Nodes (Cluster)'
                                    : (widget.state.nodes.firstWhere((n) => n.id == m.targetNode, orElse: () => Node(id: m.targetNode, ip: m.targetNode, role: 'node', status: 'active')).ip),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: m.targetNode == 'all' ? const Color(0xFF10B981) : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              m.device.length > 32 ? '${m.device.substring(0, 32)}...' : m.device,
                              style: const TextStyle(fontFamily: 'Courier New', fontSize: 12),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 14),
                              tooltip: 'Copy device path: ${m.device}',
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: m.device));
                                _showSnackBar('Copied remote device path to clipboard');
                              },
                            ),
                          ],
                        ),
                      ),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: m.mountPoint == '/var/contenedores'
                                    ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                    : (isDark ? Colors.grey[800] : Colors.grey[200]),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                m.mountPoint,
                                style: TextStyle(
                                  fontFamily: 'Courier New',
                                  fontSize: 12,
                                  fontWeight: m.mountPoint == '/var/contenedores' ? FontWeight.bold : FontWeight.normal,
                                  color: m.mountPoint == '/var/contenedores' ? const Color(0xFF10B981) : null,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 14),
                              tooltip: 'Copy mount point',
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: m.mountPoint));
                                _showSnackBar('Copied mount point');
                              },
                            ),
                          ],
                        ),
                      ),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              m.autoMount ? Icons.check_circle : Icons.cancel_outlined,
                              size: 16,
                              color: m.autoMount ? const Color(0xFF10B981) : Colors.grey,
                            ),
                            const SizedBox(width: 4),
                            Text(m.autoMount ? '/etc/fstab' : 'Manual', style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                      DataCell(
                        Tooltip(
                          message: m.errorMessage ?? (m.status == 'mounted' ? 'Filesystem is live and mounted' : 'Unmounted'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  m.status.toUpperCase(),
                                  style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (m.status == 'mounted')
                              IconButton(
                                icon: const Icon(Icons.eject_outlined, size: 18, color: Colors.orange),
                                tooltip: 'Unmount (${m.mountPoint})',
                                onPressed: () async {
                                  try {
                                    _showSnackBar('Unmounting ${m.mountPoint}...');
                                    await ApiService.unmountStorageEntry(m.id);
                                    _showSnackBar('Unmounted successfully');
                                    _loadAllData();
                                  } catch (e) {
                                    _showSnackBar('Failed to unmount: $e', isError: true);
                                  }
                                },
                              )
                            else
                              IconButton(
                                icon: const Icon(Icons.play_arrow, size: 18, color: Color(0xFF10B981)),
                                tooltip: 'Mount (${m.mountPoint})',
                                onPressed: () async {
                                  try {
                                    _showSnackBar('Mounting ${m.mountPoint}...');
                                    await ApiService.mountStorageEntry(m.id);
                                    _showSnackBar('Mounted successfully');
                                    _loadAllData();
                                  } catch (e) {
                                    _showSnackBar('Failed to mount: $e', isError: true);
                                  }
                                },
                              ),
                            IconButton(
                              icon: const Icon(Icons.speed, size: 18, color: Color(0xFF3B82F6)),
                              tooltip: 'Test Connection & Latency',
                              onPressed: () async {
                                try {
                                  _showSnackBar('Testing remote share connectivity...');
                                  final res = await ApiService.testStorageMount({
                                    'name': m.name,
                                    'device': m.device,
                                    'mount_point': m.mountPoint,
                                    'fs_type': m.fsType,
                                    'options': m.options,
                                  });
                                  if (res.success) {
                                    _showSnackBar('✅ Connected! Latency: ${res.latencyMs}ms | Writable: ${res.isWritable ? "Yes" : "Read-Only"}');
                                  } else {
                                    _showSnackBar('❌ Test Failed: ${res.errorMessage}', isError: true);
                                  }
                                } catch (e) {
                                  _showSnackBar('Test error: $e', isError: true);
                                }
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                              tooltip: 'Delete Mount & Clean /etc/fstab',
                              onPressed: () => _showDeleteMountDialog(m),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  // ── Dialogs: Mount Wizard & fstab Inspector ────────────────────────

  void _showAddMountDialog() {
    String protocol = 'nfs'; // nfs, cifs, s3, custom
    final nameCtrl = TextEditingController(text: 'nfs-var-contenedores');
    final deviceCtrl = TextEditingController(text: '192.168.1.50:/volume1/contenedores');
    final mountPointCtrl = TextEditingController(text: '/var/contenedores');
    final optionsCtrl = TextEditingController(text: 'rw,hard,intr,noatime,rsize=1048576,wsize=1048576,_netdev');
    final descCtrl = TextEditingController(text: 'Primary shared NFS pool for multi-node container mobility');
    bool autoMount = true;
    String selectedTargetNode = 'all';

    // Protocol specifics
    final userCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final domainCtrl = TextEditingController();
    final s3EndpointCtrl = TextEditingController(text: 'https://s3.amazonaws.com');
    final s3AccessKeyCtrl = TextEditingController();
    final s3SecretKeyCtrl = TextEditingController();

    TestMountResultModel? testResult;
    bool isTesting = false;
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.dns, color: Color(0xFF10B981)),
                  SizedBox(width: 8),
                  Text('Add Network Filesystem / Mount'),
                ],
              ),
              content: SizedBox(
                width: 580,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Protocol Selector
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'nfs', label: Text('NFS v3/v4'), icon: Icon(Icons.storage, size: 16)),
                          ButtonSegment(value: 'glusterfs', label: Text('GlusterFS'), icon: Icon(Icons.hub, size: 16)),
                          ButtonSegment(value: 'cifs', label: Text('Samba / CIFS'), icon: Icon(Icons.folder_shared, size: 16)),
                          ButtonSegment(value: 's3', label: Text('S3 Object'), icon: Icon(Icons.cloud_queue, size: 16)),
                          ButtonSegment(value: 'custom', label: Text('POSIX'), icon: Icon(Icons.settings, size: 16)),
                        ],
                        selected: {protocol},
                        onSelectionChanged: (newSet) {
                          final selected = newSet.first;
                          setDlgState(() {
                            protocol = selected;
                            if (protocol == 'nfs') {
                              nameCtrl.text = 'nfs-var-contenedores';
                              deviceCtrl.text = '192.168.1.50:/volume1/contenedores';
                              mountPointCtrl.text = '/var/contenedores';
                              optionsCtrl.text = 'rw,hard,intr,noatime,rsize=1048576,wsize=1048576,_netdev';
                              descCtrl.text = 'Shared NFS volume for container mobility';
                            } else if (protocol == 'glusterfs') {
                              final defaultVol = _glusterVolumes.isNotEmpty ? _glusterVolumes.first.name : 'gv_contenedores';
                              nameCtrl.text = 'gluster-$defaultVol';
                              deviceCtrl.text = 'localhost:$defaultVol';
                              mountPointCtrl.text = '/var/contenedores';
                              optionsCtrl.text = 'defaults,_netdev';
                              descCtrl.text = 'GlusterFS 3-way replicated cluster volume';
                            } else if (protocol == 'cifs') {
                              nameCtrl.text = 'samba-shared-data';
                              deviceCtrl.text = '//192.168.1.50/docker_share';
                              mountPointCtrl.text = '/var/contenedores';
                              optionsCtrl.text = 'rw,_netdev,uid=1000,gid=1000';
                              descCtrl.text = 'Windows / TrueNAS Samba network share';
                            } else if (protocol == 's3') {
                              nameCtrl.text = 's3-bucket-data';
                              deviceCtrl.text = 's3fs#my-gubernator-bucket';
                              mountPointCtrl.text = '/var/contenedores/s3-data';
                              optionsCtrl.text = '_netdev,allow_other,use_cache=/tmp,uid=1000,gid=1000';
                              descCtrl.text = 'S3 FUSE object storage bucket mount';
                            } else {
                              nameCtrl.text = 'block-device-mount';
                              deviceCtrl.text = '/dev/sdb1';
                              mountPointCtrl.text = '/var/contenedores';
                              optionsCtrl.text = 'defaults,_netdev';
                              descCtrl.text = 'Direct block device mount';
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 16),

                      // Common Fields
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(labelText: 'Mount Identifier / Name', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 12),

                      DropdownButtonFormField<String>(
                        value: selectedTargetNode,
                        decoration: const InputDecoration(
                          labelText: 'Target Centurion Host',
                          helperText: 'Select "All Centurions" for cluster-wide container mobility, or target a specific node.',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.computer, size: 20),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: 'all',
                            child: Text('🌐 All Centurions (Cluster-Wide Swarm Mobility)'),
                          ),
                          ...widget.state.nodes.map(
                            (node) => DropdownMenuItem(
                              value: node.id,
                              child: Text('💻 ${node.role.toUpperCase()}: ${node.ip} (${node.id})'),
                            ),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) setDlgState(() => selectedTargetNode = val);
                        },
                      ),
                      const SizedBox(height: 12),

                      TextField(
                        controller: deviceCtrl,
                        decoration: InputDecoration(
                          labelText: protocol == 'nfs'
                              ? 'NFS Server & Export Path'
                              : (protocol == 'cifs' ? 'Samba Share Path' : (protocol == 's3' ? 'S3 Bucket Name (e.g. s3fs#my-bucket)' : 'Device / Source Path')),
                          hintText: protocol == 'nfs' ? '192.168.1.50:/volume1/contenedores' : (protocol == 'cifs' ? '//192.168.1.50/share' : 'my-bucket'),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),

                      TextField(
                        controller: mountPointCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Destination Mount Point',
                          hintText: '/var/contenedores',
                          helperText: 'Default /var/contenedores enables instant multi-node container mobility.',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Protocol Specific Credentials
                      if (protocol == 'cifs') ...[
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: userCtrl,
                                decoration: const InputDecoration(labelText: 'Samba Username', border: OutlineInputBorder()),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: passCtrl,
                                obscureText: true,
                                decoration: const InputDecoration(labelText: 'Samba Password', border: OutlineInputBorder()),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: domainCtrl,
                          decoration: const InputDecoration(labelText: 'Workgroup / Domain (optional)', border: OutlineInputBorder()),
                        ),
                        const SizedBox(height: 12),
                      ] else if (protocol == 's3') ...[
                        TextField(
                          controller: s3EndpointCtrl,
                          decoration: const InputDecoration(
                            labelText: 'S3 API Endpoint (AWS, MinIO, Wasabi, Cloudflare R2)',
                            hintText: 'https://s3.amazonaws.com or https://minio.internal.lan:9000',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: s3AccessKeyCtrl,
                                decoration: const InputDecoration(labelText: 'Access Key ID', border: OutlineInputBorder()),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: s3SecretKeyCtrl,
                                obscureText: true,
                                decoration: const InputDecoration(labelText: 'Secret Access Key', border: OutlineInputBorder()),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],

                      TextField(
                        controller: optionsCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Mount Options String',
                          hintText: 'rw,_netdev,rsize=1048576',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),

                      TextField(
                        controller: descCtrl,
                        decoration: const InputDecoration(labelText: 'Description / Notes', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 12),

                      SwitchListTile(
                        title: const Text('Persist in /etc/fstab'),
                        subtitle: const Text('Automatically mount on Centurion boot'),
                        value: autoMount,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (val) => setDlgState(() => autoMount = val),
                      ),

                      if (testResult != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: testResult!.success ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: testResult!.success ? Colors.green : Colors.redAccent),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(testResult!.success ? Icons.check_circle : Icons.error, color: testResult!.success ? Colors.green : Colors.redAccent, size: 18),
                                  const SizedBox(width: 6),
                                  Text(
                                    testResult!.success ? 'Test Successful (Latency: ${testResult!.latencyMs}ms)' : 'Mount Test Failed',
                                    style: TextStyle(fontWeight: FontWeight.bold, color: testResult!.success ? Colors.green : Colors.redAccent),
                                  ),
                                ],
                              ),
                              if (testResult!.success) ...[
                                const SizedBox(height: 4),
                                Text(
                                  '• Writable: ${testResult!.isWritable ? "Yes (R/W Verified)" : "Read-Only"}\n• Available Capacity: ${(testResult!.freeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ] else ...[
                                const SizedBox(height: 4),
                                Text(testResult!.errorMessage ?? 'Unknown error', style: const TextStyle(fontSize: 12, color: Colors.redAccent)),
                              ],
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
                  icon: isTesting ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.speed, size: 16),
                  label: const Text('Test Connection'),
                  onPressed: isTesting
                      ? null
                      : () async {
                          setDlgState(() => isTesting = true);
                          try {
                            String fst = protocol;
                            if (protocol == 's3') fst = 'fuse.s3fs';
                            final res = await ApiService.testStorageMount({
                              'name': nameCtrl.text.trim(),
                              'device': deviceCtrl.text.trim(),
                              'mount_point': mountPointCtrl.text.trim(),
                              'fs_type': fst,
                              'options': optionsCtrl.text.trim(),
                              'username': userCtrl.text.trim(),
                              'password': passCtrl.text.trim(),
                              'domain': domainCtrl.text.trim(),
                              's3_endpoint': s3EndpointCtrl.text.trim(),
                              's3_access_key': s3AccessKeyCtrl.text.trim(),
                              's3_secret_key': s3SecretKeyCtrl.text.trim(),
                            });
                            setDlgState(() {
                              testResult = res;
                              isTesting = false;
                            });
                          } catch (e) {
                            setDlgState(() {
                              testResult = TestMountResultModel(success: false, errorMessage: e.toString());
                              isTesting = false;
                            });
                          }
                        },
                ),
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                  icon: isSaving ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save, size: 16),
                  label: const Text('Save & Mount'),
                  onPressed: isSaving
                      ? null
                      : () async {
                          setDlgState(() => isSaving = true);
                          try {
                            String fst = protocol;
                            if (protocol == 's3') fst = 'fuse.s3fs';
                            await ApiService.createStorageMount({
                              'name': nameCtrl.text.trim(),
                              'device': deviceCtrl.text.trim(),
                              'mount_point': mountPointCtrl.text.trim(),
                              'fs_type': fst,
                              'options': optionsCtrl.text.trim(),
                              'target_node': selectedTargetNode,
                              'auto_mount': autoMount,
                              'description': descCtrl.text.trim(),
                              'username': userCtrl.text.trim(),
                              'password': passCtrl.text.trim(),
                              'domain': domainCtrl.text.trim(),
                              's3_endpoint': s3EndpointCtrl.text.trim(),
                              's3_access_key': s3AccessKeyCtrl.text.trim(),
                              's3_secret_key': s3SecretKeyCtrl.text.trim(),
                            });
                            Navigator.pop(ctx);
                            _showSnackBar('✅ Network mount created and mounted successfully!');
                            _loadAllData();
                          } catch (e) {
                            setDlgState(() => isSaving = false);
                            _showSnackBar('❌ Failed to create mount: $e', isError: true);
                          }
                        },
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showMountAllDialog() {
    String selectedNode = 'all';
    bool isExecuting = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.sync, color: Color(0xFF3B82F6)),
                  SizedBox(width: 8),
                  Text('Execute mount -a (Mount All Entries)'),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Select target Centurion host(s) on which to execute "mount -a":'),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedNode,
                      decoration: const InputDecoration(
                        labelText: 'Target Centurion Host',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.computer, size: 20),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: 'all',
                          child: Text('🌐 All Centurions (Execute across whole cluster)'),
                        ),
                        ...widget.state.nodes.map(
                          (node) => DropdownMenuItem(
                            value: node.id,
                            child: Text('💻 ${node.role.toUpperCase()}: ${node.ip} (${node.id})'),
                          ),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) setDlgState(() => selectedNode = val);
                      },
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'This executes "mount -a" to reload and mount all filesystems described in /etc/fstab on the selected host(s).',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF3B82F6)),
                  icon: isExecuting
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.play_arrow, size: 16),
                  label: const Text('Execute mount -a'),
                  onPressed: isExecuting
                      ? null
                      : () async {
                          setDlgState(() => isExecuting = true);
                          try {
                            final out = await ApiService.mountAllStorageEntries(targetNode: selectedNode);
                            Navigator.pop(ctx);
                            _showMountAllResultDialog(out);
                            _loadAllData();
                          } catch (e) {
                            setDlgState(() => isExecuting = false);
                            _showSnackBar('Failed to execute mount -a: $e', isError: true);
                          }
                        },
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showMountAllResultDialog(String output) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Color(0xFF10B981)),
              SizedBox(width: 8),
              Text('mount -a Execution Results'),
            ],
          ),
          content: SizedBox(
            width: 550,
            child: SingleChildScrollView(
              child: SelectableText(
                output,
                style: const TextStyle(fontFamily: 'Courier New', fontSize: 12),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ],
        );
      },
    );
  }

  void _showFstabViewerDialog() {
    String selectedNode = 'all';
    final contentCtrl = TextEditingController();
    bool isLoading = true;
    bool isSaving = false;
    String filePath = '/etc/fstab';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            void loadFstabForNode(String node) async {
              setDlgState(() => isLoading = true);
              try {
                final fstabData = await ApiService.fetchRawFstab(node: node);
                filePath = fstabData['path'] ?? '/etc/fstab';
                contentCtrl.text = fstabData['raw'] ?? '';
                setDlgState(() => isLoading = false);
              } catch (e) {
                setDlgState(() => isLoading = false);
                _showSnackBar('Failed to read /etc/fstab from $node: $e', isError: true);
              }
            }

            // Initial load
            if (isLoading && contentCtrl.text.isEmpty) {
              loadFstabForNode(selectedNode);
            }

            final isDark = Theme.of(context).brightness == Brightness.dark;
            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.tune, color: Color(0xFF3B82F6)),
                  const SizedBox(width: 8),
                  const Text('Host Configuration Editor: /etc/fstab'),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      'Target: $selectedNode',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF3B82F6)),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 750,
                height: 520,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Node selector bar
                    Row(
                      children: [
                        const Text('Centurion Node:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: selectedNode,
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: 'all',
                                child: Text('🌐 All Centurions (Sync across all cluster nodes)'),
                              ),
                              ...widget.state.nodes.map(
                                (node) => DropdownMenuItem(
                                  value: node.id,
                                  child: Text('💻 ${node.role.toUpperCase()}: ${node.ip} (${node.id})'),
                                ),
                              ),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                selectedNode = val;
                                loadFstabForNode(val);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.refresh, size: 20),
                          tooltip: 'Reload from host',
                          onPressed: () => loadFstabForNode(selectedNode),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Live configuration file path: $filePath (Automatic timestamped backups generated on save)',
                      style: TextStyle(fontSize: 12, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: isDark ? const Color(0xFF334155) : Colors.grey[300]!),
                              ),
                              child: TextField(
                                controller: contentCtrl,
                                maxLines: null,
                                expands: true,
                                style: TextStyle(
                                  fontFamily: 'Courier New',
                                  fontSize: 12.5,
                                  color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B),
                                ),
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.all(4),
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy Content'),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: contentCtrl.text));
                    _showSnackBar('Copied /etc/fstab content to clipboard');
                  },
                ),
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                  icon: isSaving
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save, size: 16),
                  label: Text('Save & Apply to ${selectedNode == "all" ? "All Nodes" : selectedNode}'),
                  onPressed: isSaving || isLoading
                      ? null
                      : () async {
                          setDlgState(() => isSaving = true);
                          try {
                            final msg = await ApiService.saveRawFstab(contentCtrl.text, node: selectedNode);
                            Navigator.pop(ctx);
                            _showSnackBar('✅ $msg');
                            _loadAllData();
                          } catch (e) {
                            setDlgState(() => isSaving = false);
                            _showSnackBar('❌ Failed to save /etc/fstab: $e', isError: true);
                          }
                        },
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 6. GLUSTERFS CLUSTER STORAGE TAB (3-Way Mirror / Replica 3 / Arbiter)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildGlusterTab(bool isDark) {
    final diag = _glusterDiag;
    final isHealthy = (diag?.healthScore ?? 100) >= 80;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Diagnostics & Actions Bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isHealthy
                    ? const Color(0xFF10B981).withValues(alpha: 0.3)
                    : Colors.orangeAccent.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: isHealthy
                          ? const Color(0xFF10B981).withValues(alpha: 0.15)
                          : Colors.orangeAccent.withValues(alpha: 0.15),
                      child: Icon(
                        Icons.hub,
                        color: isHealthy ? const Color(0xFF10B981) : Colors.orangeAccent,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'GlusterFS Multi-Node Storage Mesh',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: (diag?.daemonRunning == true ? const Color(0xFF10B981) : Colors.orange)
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                diag?.daemonRunning == true ? 'DAEMON ACTIVE' : 'DAEMON INACTIVE',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: diag?.daemonRunning == true ? const Color(0xFF10B981) : Colors.orange,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Dedicated Storage Network (enp0s2: 10.10.100.0/24) • CoreDNS (*.storage.gbnt.local) • Cockpit Total Management Suite',
                          style: TextStyle(fontSize: 12, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                        ),
                      ],
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 20),
                      tooltip: 'Refresh GlusterFS Storage Mesh',
                      onPressed: _loadAllData,
                    ),
                    const SizedBox(width: 4),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.person_add_outlined, size: 16),
                      label: const Text('Probe Peer'),
                      onPressed: _showProbePeerDialog,
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Create Cluster Volume'),
                      onPressed: _showCreateGlusterVolumeDialog,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 12),

                // KPI Status Badges
                Row(
                  children: [
                    _buildGlusterKpi('Health Score', '${diag?.healthScore ?? 100}%', isHealthy ? const Color(0xFF10B981) : Colors.orange, Icons.health_and_safety_outlined),
                    const SizedBox(width: 16),
                    _buildGlusterKpi('Storage Pool Peers', '${_glusterPeers.length} Nodes', const Color(0xFF3B82F6), Icons.group_work_outlined),
                    const SizedBox(width: 16),
                    _buildGlusterKpi('Replicated Volumes', '${_glusterVolumes.length} Volumes', const Color(0xFF8B5CF6), Icons.layers_outlined),
                    const SizedBox(width: 16),
                    _buildGlusterKpi('Storage Network', '10.10.100.0/24 (enp0s2)', const Color(0xFF10B981), Icons.settings_ethernet),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Cockpit Sub-Navigation Bar ─────────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildGlusterSubTabItem(0, 'Volumes & Peers', Icons.layers_outlined, isDark),
                const SizedBox(width: 8),
                _buildGlusterSubTabItem(1, 'Performance & I/O (Cockpit)', Icons.speed, isDark),
                const SizedBox(width: 8),
                _buildGlusterSubTabItem(2, 'Storage Network (Dual NIC)', Icons.settings_ethernet, isDark),
                const SizedBox(width: 8),
                _buildGlusterSubTabItem(3, 'Quotas & Directory Limits', Icons.data_usage_outlined, isDark),
                const SizedBox(width: 8),
                _buildGlusterSubTabItem(4, 'Volume Snapshots', Icons.camera_alt_outlined, isDark),
                const SizedBox(width: 8),
                _buildGlusterSubTabItem(5, 'Advanced Tuning Options', Icons.tune, isDark),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Render Selected Sub-View
          if (_glusterSubTab == 0)
            _buildGlusterOverviewSubTab(isDark)
          else if (_glusterSubTab == 1)
            _buildGlusterPerformanceSubTab(isDark)
          else if (_glusterSubTab == 2)
            _buildGlusterNetworkSubTab(isDark)
          else if (_glusterSubTab == 3)
            _buildGlusterQuotasSubTab(isDark)
          else if (_glusterSubTab == 4)
            _buildGlusterSnapshotsSubTab(isDark)
          else
            _buildGlusterOptionsSubTab(isDark),
        ],
      ),
    );
  }

  Widget _buildGlusterSubTabItem(int index, String label, IconData icon, bool isDark) {
    final isSelected = _glusterSubTab == index;
    return InkWell(
      onTap: () {
        setState(() => _glusterSubTab = index);
        if (index == 1 && _selectedGlusterVolumeForProfile.isNotEmpty) {
          _fetchProfileData(_selectedGlusterVolumeForProfile);
        } else if (index == 3 && _selectedGlusterVolumeForProfile.isNotEmpty) {
          _fetchQuotasData(_selectedGlusterVolumeForProfile);
        }
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF10B981).withValues(alpha: 0.18)
              : (isDark ? const Color(0xFF1E293B) : Colors.white),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF10B981)
                : (isDark ? const Color(0xFF334155) : Colors.grey[300]!),
            width: isSelected ? 1.5 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF10B981).withValues(alpha: 0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isSelected ? const Color(0xFF10B981) : (isDark ? Colors.grey[300] : Colors.grey[700])),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? const Color(0xFF10B981) : (isDark ? Colors.grey[300] : Colors.grey[800]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlusterOverviewSubTab(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Trusted Storage Pool Peers Section ─────────────────────────────
        Row(
          children: [
            const Icon(Icons.people_outline, size: 18, color: Color(0xFF3B82F6)),
            const SizedBox(width: 8),
            const Text(
              'Trusted Storage Pool Peers (Centurions)',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            Text(
              '${_glusterPeers.where((p) => p.connected).length}/${_glusterPeers.length} Peers Connected',
              style: TextStyle(fontSize: 12, color: Colors.grey[400]),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Peer Cards Grid
        if (_glusterPeers.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('No GlusterFS peers found. Use "Probe Peer" or run ansible/glusterfs.yml to initialize.'),
          )
        else
          Row(
            children: _glusterPeers.map((p) {
              return Expanded(
                child: Container(
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: p.connected
                          ? const Color(0xFF10B981).withValues(alpha: 0.3)
                          : Colors.redAccent.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            p.isLocal ? Icons.security : Icons.dns_outlined,
                            size: 16,
                            color: const Color(0xFF3B82F6),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              p.hostname,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: (p.connected ? const Color(0xFF10B981) : Colors.redAccent)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              p.connected ? 'CONNECTED' : 'DISCONNECTED',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: p.connected ? const Color(0xFF10B981) : Colors.redAccent,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        p.uuid.isNotEmpty ? 'UUID: ${p.uuid.substring(0, 13)}...' : 'Local Manager Node',
                        style: TextStyle(fontSize: 11, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.speed, size: 12, color: Colors.grey[400]),
                          const SizedBox(width: 4),
                          Text(
                            p.pingMs > 0 ? '${p.pingMs} ms latency' : '0.4 ms (Storage mesh)',
                            style: TextStyle(fontSize: 11, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        const SizedBox(height: 24),

        // ── GlusterFS Volumes Section ─────────────────────────────────────
        Row(
          children: [
            const Icon(Icons.layers_outlined, size: 18, color: Color(0xFF10B981)),
            const SizedBox(width: 8),
            const Text(
              'Replicated Storage Volumes',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            if (_glusterVolumes.isNotEmpty) ...[
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                label: const Text('Delete All Volumes'),
                onPressed: _showDeleteAllGlusterVolumesDialog,
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New Volume', style: TextStyle(fontSize: 12)),
                onPressed: _showCreateGlusterVolumeDialog,
              ),
              const SizedBox(width: 12),
            ],
            Text(
              '${_glusterVolumes.length} Managed Volumes',
              style: TextStyle(fontSize: 12, color: Colors.grey[400]),
            ),
          ],
        ),
        const SizedBox(height: 12),

        if (_glusterVolumes.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isDark ? const Color(0xFF334155) : Colors.grey[300]!),
            ),
            child: Column(
              children: [
                const Icon(Icons.hub_outlined, size: 48, color: Color(0xFF10B981)),
                const SizedBox(height: 12),
                const Text(
                  'No GlusterFS Cluster Volumes Configured',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 6),
                Text(
                  'Create a 3-way replicated volume across your Centurions over the dedicated storage network (10.10.100.0/24).',
                  style: TextStyle(color: Colors.grey[400], fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                  icon: const Icon(Icons.add),
                  label: const Text('Create Replicated Volume (Replica 3)'),
                  onPressed: _showCreateGlusterVolumeDialog,
                ),
              ],
            ),
          )
        else
          Column(
            children: _glusterVolumes.map((vol) => _buildVolumeCard(vol, isDark)).toList(),
          ),
      ],
    );
  }

  // ── Cockpit-Storaged I/O Performance & Profiling Sub-Tab ──────────────────
  Widget _buildGlusterPerformanceSubTab(bool isDark) {
    final report = _activeProfileReport;
    final isProfiling = report?.isProfiling ?? false;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? const Color(0xFF334155) : Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.speed, color: Color(0xFF10B981), size: 20),
              const SizedBox(width: 8),
              const Text('Volume I/O Profiling (Cockpit Storaged Engine)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const Spacer(),
              if (_glusterVolumes.isNotEmpty)
                DropdownButton<String>(
                  value: _selectedGlusterVolumeForProfile.isNotEmpty ? _selectedGlusterVolumeForProfile : _glusterVolumes.first.name,
                  items: _glusterVolumes.map((v) => DropdownMenuItem(value: v.name, child: Text('Volume: ${v.name}'))).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedGlusterVolumeForProfile = val);
                      _fetchProfileData(val);
                    }
                  },
                ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                icon: Icon(isProfiling ? Icons.stop : Icons.play_arrow, size: 16, color: isProfiling ? Colors.redAccent : const Color(0xFF10B981)),
                label: Text(isProfiling ? 'Stop Profiling' : 'Start Profiling', style: TextStyle(color: isProfiling ? Colors.redAccent : const Color(0xFF10B981))),
                onPressed: () async {
                  if (_selectedGlusterVolumeForProfile.isEmpty) return;
                  try {
                    if (isProfiling) {
                      await ApiService.stopGlusterVolumeProfile(_selectedGlusterVolumeForProfile);
                      _showSnackBar('Profiling stopped for $_selectedGlusterVolumeForProfile');
                    } else {
                      await ApiService.startGlusterVolumeProfile(_selectedGlusterVolumeForProfile);
                      _showSnackBar('Profiling started for $_selectedGlusterVolumeForProfile');
                    }
                    _fetchProfileData(_selectedGlusterVolumeForProfile);
                  } catch (e) {
                    _showSnackBar('Failed to toggle profiling: $e', isError: true);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Speedometer KPIs
          Row(
            children: [
              _buildGlusterMetricCard('Total IOPS', '${report?.totalIOPS ?? 0} IOPS', const Color(0xFF10B981), Icons.bolt, isDark),
              const SizedBox(width: 12),
              _buildGlusterMetricCard('Read Throughput', '${(report?.totalReadMBs ?? 0).toStringAsFixed(1)} MB/s', const Color(0xFF3B82F6), Icons.download, isDark),
              const SizedBox(width: 12),
              _buildGlusterMetricCard('Write Throughput', '${(report?.totalWriteMBs ?? 0).toStringAsFixed(1)} MB/s', const Color(0xFF8B5CF6), Icons.upload, isDark),
              const SizedBox(width: 12),
              _buildGlusterMetricCard('Average Latency', '${(report?.avgLatencyMs ?? 0).toStringAsFixed(2)} ms', Colors.amber, Icons.timer_outlined, isDark),
            ],
          ),
          const SizedBox(height: 20),

          // FOP Operations Breakdown Table
          const Text('File Operations (FOP) Breakdown:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
          const SizedBox(height: 8),
          if (report == null || report.topOperations.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No profiling data collected yet. Click "Start Profiling" to begin sampling block operations.', style: TextStyle(fontSize: 12, color: Colors.grey)),
            )
          else
            Table(
              columnWidths: const {
                0: FlexColumnWidth(2),
                1: FlexColumnWidth(2),
                2: FlexColumnWidth(2),
                3: FlexColumnWidth(2),
                4: FlexColumnWidth(2),
              },
              children: [
                TableRow(
                  decoration: BoxDecoration(color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9)),
                  children: const [
                    Padding(padding: EdgeInsets.all(8), child: Text('OPERATION', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5))),
                    Padding(padding: EdgeInsets.all(8), child: Text('HITS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5))),
                    Padding(padding: EdgeInsets.all(8), child: Text('% OF I/O', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5))),
                    Padding(padding: EdgeInsets.all(8), child: Text('AVG LATENCY', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5))),
                    Padding(padding: EdgeInsets.all(8), child: Text('MAX LATENCY', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5))),
                  ],
                ),
                ...report.topOperations.map((fop) {
                  return TableRow(
                    children: [
                      Padding(padding: const EdgeInsets.all(8), child: Text(fop.operation, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      Padding(padding: const EdgeInsets.all(8), child: Text('${fop.hits}', style: const TextStyle(fontSize: 12))),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Row(
                          children: [
                            Expanded(
                              child: LinearProgressIndicator(
                                value: (fop.percentage / 100).clamp(0.0, 1.0),
                                color: const Color(0xFF10B981),
                                backgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text('${fop.percentage.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 11)),
                          ],
                        ),
                      ),
                      Padding(padding: const EdgeInsets.all(8), child: Text('${fop.avgLatencyUs.toStringAsFixed(1)} μs', style: const TextStyle(fontSize: 12))),
                      Padding(padding: const EdgeInsets.all(8), child: Text('${fop.maxLatencyUs.toStringAsFixed(1)} μs', style: const TextStyle(fontSize: 12))),
                    ],
                  );
                }),
              ],
            ),
          const SizedBox(height: 20),

          // Block Size Distribution
          const Text('Block Size Distribution Histogram:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
          const SizedBox(height: 8),
          if (report != null && report.blockSizeProfile.isNotEmpty)
            Row(
              children: report.blockSizeProfile.map((b) {
                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: isDark ? const Color(0xFF334155) : Colors.grey[300]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(b.range, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        const SizedBox(height: 4),
                        Text('Reads: ${b.readHits} | Writes: ${b.writeHits}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  // ── Dedicated Storage Network (Dual NIC & CoreDNS) Sub-Tab ────────────────
  Widget _buildGlusterNetworkSubTab(bool isDark) {
    final net = _storageNetworkReport;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Network Overview Banner
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.settings_ethernet, color: Color(0xFF10B981), size: 22),
                  const SizedBox(width: 10),
                  const Text('Dedicated Storage Network (Dual-NIC Architecture)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('SUBNET: ${net.dedicatedSubnet}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF10B981))),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('DNS: ${net.corednsSuffix}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF3B82F6))),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Centurion nodes use a dedicated virtual network interface (enp0s2) exclusively for GlusterFS replication streams, brick communication, and FUSE mount transport to prevent interference with application traffic on enp0s1.',
                style: TextStyle(fontSize: 12.5, color: Colors.grey),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _buildGlusterMetricCard('Cluster Storage Rx Rate', '${net.totalRxRateMBs.toStringAsFixed(2)} MB/s', const Color(0xFF10B981), Icons.arrow_downward, isDark),
                  const SizedBox(width: 12),
                  _buildGlusterMetricCard('Cluster Storage Tx Rate', '${net.totalTxRateMBs.toStringAsFixed(2)} MB/s', const Color(0xFF3B82F6), Icons.arrow_upward, isDark),
                  const SizedBox(width: 12),
                  _buildGlusterMetricCard('Dedicated NIC Status', 'enp0s2 (UP & Active)', const Color(0xFF8B5CF6), Icons.check_circle_outline, isDark),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Node Cards Grid
        const Text('Centurion Storage Interfaces & Live Traffic:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 10),

        ...net.nodes.map((node) {
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isDark ? const Color(0xFF334155) : Colors.grey[300]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(node.nodeRole == 'manager' ? Icons.security : Icons.computer, size: 18, color: const Color(0xFF3B82F6)),
                    const SizedBox(width: 8),
                    Text('${node.nodeRole.toUpperCase()}: ${node.nodeId}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('STORAGE IP: ${node.storageIp.isNotEmpty ? node.storageIp : "10.10.100.x"}', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('DNS: ${node.storageDns}', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF3B82F6))),
                    ),
                    const Spacer(),
                    Text('Management IP: ${node.hostIp}', style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
                  ],
                ),
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 10),

                // Interface rows
                ...node.interfaces.map((iface) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(iface.isStorage ? Icons.star : Icons.alt_route, size: 14, color: iface.isStorage ? const Color(0xFF10B981) : Colors.grey),
                        const SizedBox(width: 6),
                        Text(iface.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'Courier New')),
                        const SizedBox(width: 8),
                        if (iface.isStorage)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(color: const Color(0xFF10B981).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                            child: const Text('DEDICATED STORAGE NIC', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                          ),
                        const Spacer(),
                        Text('Rx: ${iface.rxRateMBs.toStringAsFixed(2)} MB/s', style: const TextStyle(fontSize: 11.5, color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
                        const SizedBox(width: 14),
                        Text('Tx: ${iface.txRateMBs.toStringAsFixed(2)} MB/s', style: const TextStyle(fontSize: 11.5, color: Color(0xFF3B82F6), fontWeight: FontWeight.bold)),
                        const SizedBox(width: 14),
                        Text('Total: ${_formatBytes(iface.rxBytes + iface.txBytes)}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  );
                }),
              ],
            ),
          );
        }),
      ],
    );
  }

  // ── Quotas & Directory Limits Sub-Tab ─────────────────────────────────────
  Widget _buildGlusterQuotasSubTab(bool isDark) {
    final quotasReport = _activeQuotasReport;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? const Color(0xFF334155) : Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.data_usage_outlined, color: Color(0xFF10B981), size: 20),
              const SizedBox(width: 8),
              const Text('Volume Quotas & Path Limits', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const Spacer(),
              if (_glusterVolumes.isNotEmpty)
                DropdownButton<String>(
                  value: _selectedGlusterVolumeForProfile.isNotEmpty ? _selectedGlusterVolumeForProfile : _glusterVolumes.first.name,
                  items: _glusterVolumes.map((v) => DropdownMenuItem(value: v.name, child: Text('Volume: ${v.name}'))).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedGlusterVolumeForProfile = val);
                      _fetchQuotasData(val);
                    }
                  },
                ),
              const SizedBox(width: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Set Path Quota'),
                onPressed: () => _showSetQuotaDialog(_selectedGlusterVolumeForProfile),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (quotasReport == null || quotasReport.quotas.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('No path quotas configured for this volume. Click "Set Path Quota" to restrict directory disk consumption.', style: TextStyle(fontSize: 12.5, color: Colors.grey)),
            )
          else
            Column(
              children: quotasReport.quotas.map((q) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isDark ? const Color(0xFF334155) : Colors.grey[300]!),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.folder, size: 18, color: Color(0xFF3B82F6)),
                      const SizedBox(width: 8),
                      Text(q.path, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'Courier New')),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: const Color(0xFF10B981).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                        child: Text('LIMIT: ${q.hardLimit}', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                      ),
                      const Spacer(),
                      Text('${q.usedMB.toStringAsFixed(1)} MB used', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  // ── Snapshots & Rollback Sub-Tab ──────────────────────────────────────────
  Widget _buildGlusterSnapshotsSubTab(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? const Color(0xFF334155) : Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.camera_alt_outlined, color: Color(0xFF10B981), size: 20),
              const SizedBox(width: 8),
              const Text('Volume Point-in-Time Snapshots', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const Spacer(),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                icon: const Icon(Icons.add_a_photo_outlined, size: 16),
                label: const Text('Create Snapshot'),
                onPressed: () => _showCreateSnapshotDialog(_selectedGlusterVolumeForProfile.isNotEmpty ? _selectedGlusterVolumeForProfile : (_glusterVolumes.isNotEmpty ? _glusterVolumes.first.name : '')),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (_glusterSnapshots.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('No volume snapshots found. Take a snapshot to enable instantaneous rollback and disaster recovery.', style: TextStyle(fontSize: 12.5, color: Colors.grey)),
            )
          else
            Table(
              columnWidths: const {
                0: FlexColumnWidth(2),
                1: FlexColumnWidth(2),
                2: FlexColumnWidth(2),
                3: FlexColumnWidth(2),
                4: FlexColumnWidth(2),
              },
              children: [
                TableRow(
                  decoration: BoxDecoration(color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9)),
                  children: const [
                    Padding(padding: EdgeInsets.all(8), child: Text('SNAPSHOT NAME', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5))),
                    Padding(padding: EdgeInsets.all(8), child: Text('VOLUME', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5))),
                    Padding(padding: EdgeInsets.all(8), child: Text('STATUS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5))),
                    Padding(padding: EdgeInsets.all(8), child: Text('CREATED', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5))),
                    Padding(padding: EdgeInsets.all(8), child: Text('ACTIONS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5))),
                  ],
                ),
                ..._glusterSnapshots.map((s) {
                  return TableRow(
                    children: [
                      Padding(padding: const EdgeInsets.all(8), child: Text(s.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      Padding(padding: const EdgeInsets.all(8), child: Text(s.volumeName, style: const TextStyle(fontSize: 12))),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(s.status, style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 11.5)),
                      ),
                      Padding(padding: const EdgeInsets.all(8), child: Text(s.createdAt, style: const TextStyle(fontSize: 11.5, color: Colors.grey))),
                      Padding(
                        padding: const EdgeInsets.all(4),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.history, size: 16, color: Color(0xFF3B82F6)),
                              tooltip: 'Rollback to Snapshot',
                              onPressed: () async {
                                try {
                                  await ApiService.restoreGlusterSnapshot(s.name);
                                  _showSnackBar('Snapshot ${s.name} restored successfully');
                                  _loadAllData();
                                } catch (e) {
                                  _showSnackBar('Failed to restore snapshot: $e', isError: true);
                                }
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                              tooltip: 'Delete Snapshot',
                              onPressed: () async {
                                try {
                                  await ApiService.deleteGlusterSnapshot(s.name);
                                  _showSnackBar('Snapshot ${s.name} deleted');
                                  _loadAllData();
                                } catch (e) {
                                  _showSnackBar('Failed to delete snapshot: $e', isError: true);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),
        ],
      ),
    );
  }

  // ── Advanced Tuning Options Sub-Tab ───────────────────────────────────────
  // ── Advanced Tuning Options Sub-Tab ───────────────────────────────────────
  Widget _buildGlusterOptionsSubTab(bool isDark) {
    final activeVolName = _selectedGlusterVolumeForProfile.isNotEmpty
        ? _selectedGlusterVolumeForProfile
        : (_glusterVolumes.isNotEmpty ? _glusterVolumes.first.name : 'gv_contenedores');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? const Color(0xFF334155) : Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune, color: Color(0xFF10B981), size: 20),
              const SizedBox(width: 8),
              const Text('Volume Tuning & Network Access Options', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const Spacer(),
              if (_glusterVolumes.isNotEmpty)
                DropdownButton<String>(
                  value: activeVolName,
                  items: _glusterVolumes.map((v) => DropdownMenuItem(value: v.name, child: Text('Volume: ${v.name}'))).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedGlusterVolumeForProfile = val);
                  },
                ),
              const SizedBox(width: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Set Custom Option', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                onPressed: () => _showSetOptionDialog(activeVolName),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Section 1: Storage Network & Access Security Isolation
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.security, size: 16, color: Color(0xFF0284C7)),
                    SizedBox(width: 6),
                    Text(
                      'Storage Network & Security Isolation',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0284C7)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _buildOptionToggleTile(
                  'auth.allow',
                  'Restricts volume access strictly to dedicated storage subnet (e.g. 10.10.100.*, 10.0.1.* or *)',
                  '10.10.100.*',
                  activeVolName,
                  isDark,
                  icon: Icons.lan,
                  isNetwork: true,
                ),
                _buildOptionToggleTile(
                  'auth.reject',
                  'Subnet / IP Deny List: Rejects connections from unwanted public/management subnets',
                  'NONE',
                  activeVolName,
                  isDark,
                  icon: Icons.block,
                  isNetwork: true,
                ),
                _buildOptionToggleTile(
                  'network.ping-timeout',
                  'Failover network timeout (seconds) before marking an unreachable node/brick disconnected',
                  '10',
                  activeVolName,
                  isDark,
                  icon: Icons.timer,
                  isNetwork: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Section 2: Container Workload & Performance Acceleration
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.speed, size: 16, color: Color(0xFF10B981)),
                    SizedBox(width: 6),
                    Text(
                      'Container Performance & Cache Acceleration',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF10B981)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _buildOptionToggleTile(
                  'performance.write-behind',
                  'Asynchronous write aggregation and background flush for container storage workloads',
                  'on',
                  activeVolName,
                  isDark,
                ),
                _buildOptionToggleTile(
                  'performance.stat-prefetch',
                  'Aggressive directory traversal and POSIX metadata caching',
                  'on',
                  activeVolName,
                  isDark,
                ),
                _buildOptionToggleTile(
                  'performance.quick-read',
                  'Inlines small container file reads directly in directory lookups',
                  'on',
                  activeVolName,
                  isDark,
                ),
                _buildOptionToggleTile(
                  'cluster.favorite-child-policy',
                  'Automatic conflict resolution based on modified timestamp (mtime)',
                  'mtime',
                  activeVolName,
                  isDark,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionToggleTile(
    String key,
    String description,
    String value,
    String volumeName,
    bool isDark, {
    IconData? icon,
    bool isNetwork = false,
  }) {
    final badgeColor = isNetwork ? const Color(0xFF0284C7) : const Color(0xFF10B981);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isDark ? const Color(0xFF334155) : Colors.grey[300]!),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: badgeColor),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'Courier New')),
                const SizedBox(height: 2),
                Text(description, style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('VALUE: $value', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: badgeColor)),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: const Size(60, 30),
              side: BorderSide(color: badgeColor.withValues(alpha: 0.5)),
            ),
            onPressed: () => _showSetOptionDialog(volumeName, key, value),
            child: Text('Configure', style: TextStyle(fontSize: 11, color: badgeColor)),
          ),
        ],
      ),
    );
  }

  void _showSetOptionDialog(String volumeName, [String? initialKey, String? initialVal]) {
    final keyCtrl = TextEditingController(text: initialKey ?? 'auth.allow');
    final valCtrl = TextEditingController(text: initialVal ?? '10.10.100.*');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.tune, color: Color(0xFF10B981), size: 20),
            const SizedBox(width: 8),
            Text('Configure Option: $volumeName', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Configure storage network isolation, subnet access restrictions or container performance parameters on this volume.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: keyCtrl,
                decoration: const InputDecoration(
                  labelText: 'Option Key',
                  hintText: 'e.g. auth.allow, auth.reject, network.ping-timeout',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.key, size: 18),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: valCtrl,
                decoration: const InputDecoration(
                  labelText: 'Option Value',
                  hintText: 'e.g. 10.10.100.*, on, off, 10, mtime',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.data_object, size: 18),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  ActionChip(
                    label: const Text('auth.allow (10.10.100.*)', style: TextStyle(fontSize: 11)),
                    onPressed: () {
                      keyCtrl.text = 'auth.allow';
                      valCtrl.text = '10.10.100.*';
                    },
                  ),
                  ActionChip(
                    label: const Text('auth.allow (*)', style: TextStyle(fontSize: 11)),
                    onPressed: () {
                      keyCtrl.text = 'auth.allow';
                      valCtrl.text = '*';
                    },
                  ),
                  ActionChip(
                    label: const Text('network.ping-timeout (10)', style: TextStyle(fontSize: 11)),
                    onPressed: () {
                      keyCtrl.text = 'network.ping-timeout';
                      valCtrl.text = '10';
                    },
                  ),
                  ActionChip(
                    label: const Text('write-behind (on)', style: TextStyle(fontSize: 11)),
                    onPressed: () {
                      keyCtrl.text = 'performance.write-behind';
                      valCtrl.text = 'on';
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.amber),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ApiService.setGlusterVolumeOption(volumeName, keyCtrl.text.trim(), '', reset: true);
                _showSnackBar('Option ${keyCtrl.text.trim()} reset to default on $volumeName');
                _loadAllData();
              } catch (e) {
                _showSnackBar('Failed to reset option: $e', isError: true);
              }
            },
            child: const Text('Reset to Default'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ApiService.setGlusterVolumeOption(volumeName, keyCtrl.text.trim(), valCtrl.text.trim());
                _showSnackBar('Option ${keyCtrl.text.trim()}=${valCtrl.text.trim()} applied successfully on $volumeName');
                _loadAllData();
              } catch (e) {
                _showSnackBar('Failed to set option: $e', isError: true);
              }
            },
            child: const Text('Apply Option'),
          ),
        ],
      ),
    );
  }

  Widget _buildGlusterMetricCard(String label, String value, Color color, IconData icon, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isDark ? const Color(0xFF334155) : Colors.grey[300]!),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 2),
                Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _fetchProfileData(String volumeName) async {
    try {
      final rep = await ApiService.fetchGlusterVolumeProfile(volumeName);
      if (mounted) setState(() => _activeProfileReport = rep);
    } catch (_) {}
  }

  Future<void> _fetchQuotasData(String volumeName) async {
    try {
      final rep = await ApiService.fetchGlusterQuotas(volumeName);
      if (mounted) setState(() => _activeQuotasReport = rep);
    } catch (_) {}
  }

  void _showSetQuotaDialog(String volumeName) {
    final pathCtrl = TextEditingController(text: '/');
    final limitCtrl = TextEditingController(text: '50GB');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Set Quota: $volumeName'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: pathCtrl, decoration: const InputDecoration(labelText: 'Directory Path', hintText: '/app-data', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: limitCtrl, decoration: const InputDecoration(labelText: 'Hard Limit', hintText: '50GB, 100GB, 1TB', border: OutlineInputBorder())),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ApiService.setGlusterQuota(volumeName, pathCtrl.text.trim(), limitCtrl.text.trim());
                _showSnackBar('Quota configured successfully');
                _fetchQuotasData(volumeName);
              } catch (e) {
                _showSnackBar('Failed to set quota: $e', isError: true);
              }
            },
            child: const Text('Set Limit'),
          ),
        ],
      ),
    );
  }

  void _showCreateSnapshotDialog(String volumeName) {
    final nameCtrl = TextEditingController(text: 'snap_${volumeName}_${DateTime.now().millisecondsSinceEpoch % 10000}');
    final descCtrl = TextEditingController(text: 'Pre-deployment backup');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Create Snapshot: $volumeName'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Snapshot Name', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder())),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ApiService.createGlusterSnapshot(nameCtrl.text.trim(), volumeName, description: descCtrl.text.trim());
                _showSnackBar('Snapshot created successfully');
                _loadAllData();
              } catch (e) {
                _showSnackBar('Failed to create snapshot: $e', isError: true);
              }
            },
            child: const Text('Create Snapshot'),
          ),
        ],
      ),
    );
  }

  Widget _buildGlusterKpi(String label, String value, Color color, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: const TextStyle(fontSize: 12),
        ),
        Text(
          value,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }

  Widget _buildVolumeCard(GlusterVolumeModel vol, bool isDark) {
    final isStarted = vol.status == 'Started';
    final hasRegisteredMount = _mounts.any((m) => m.fsType == 'glusterfs' && (m.device.contains(vol.name) || m.name.contains(vol.name)));
    final matchingMount = _mounts.firstWhere(
      (m) => m.fsType == 'glusterfs' && (m.device.contains(vol.name) || m.name.contains(vol.name)),
      orElse: () => StorageMountModel.empty(),
    );
    final isMounted = vol.isMounted || hasRegisteredMount;
    final displayMountPoint = matchingMount.mountPoint.isNotEmpty ? matchingMount.mountPoint : (vol.mountPoint.isNotEmpty ? vol.mountPoint : '/var/contenedores');

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isStarted
              ? const Color(0xFF10B981).withValues(alpha: 0.3)
              : Colors.orange.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Volume Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Icon(Icons.layers, color: isStarted ? const Color(0xFF10B981) : Colors.orange, size: 20),
                const SizedBox(width: 10),
                Text(
                  vol.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Replica ${vol.replicaCount}${vol.arbiterCount > 0 ? ' (Arbiter 1)' : ''}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: (isStarted ? const Color(0xFF10B981) : Colors.orange).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    vol.status.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isStarted ? const Color(0xFF10B981) : Colors.orange,
                    ),
                  ),
                ),
                if (isMounted) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.link, size: 12, color: Color(0xFF10B981)),
                        const SizedBox(width: 4),
                        Text(
                          'fstab: $displayMountPoint',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.link_off, size: 12, color: Colors.amber),
                        SizedBox(width: 4),
                        Text(
                          'Unmounted in fstab',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber),
                        ),
                      ],
                    ),
                  ),
                ],
                const Spacer(),

                // Prominent Mount Action Button
                OutlinedButton.icon(
                  icon: Icon(isMounted ? Icons.sync : Icons.add_link, size: 14, color: const Color(0xFF3B82F6)),
                  label: Text(
                    isMounted ? 'Remount / fstab' : 'Mount to fstab',
                    style: const TextStyle(color: Color(0xFF3B82F6), fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: const Color(0xFF3B82F6).withValues(alpha: 0.4)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => _showMountClusterDialog(vol.name),
                ),
                const SizedBox(width: 6),

                // Action Buttons
                IconButton(
                  icon: const Icon(Icons.medical_services_outlined, size: 18, color: Color(0xFF10B981)),
                  tooltip: 'Self-Heal & Split-Brain Diagnostics',
                  onPressed: () => _showGlusterHealDialog(vol.name),
                ),
                if (isStarted)
                  IconButton(
                    icon: const Icon(Icons.stop_circle_outlined, size: 18, color: Colors.orange),
                    tooltip: 'Stop Volume',
                    onPressed: () => _stopGlusterVolume(vol.name),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.play_circle_outline, size: 18, color: Color(0xFF10B981)),
                    tooltip: 'Start Volume',
                    onPressed: () => _startGlusterVolume(vol.name),
                  ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                  tooltip: 'Delete Volume',
                  onPressed: () => _showDeleteGlusterVolumeDialog(vol),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Capacity Bar
                if (vol.capacityTotal > 0) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Disk Capacity Usage', style: TextStyle(fontSize: 12, color: isDark ? Colors.grey[400] : Colors.grey[600])),
                      Text(
                        '${vol.capacityPercent.toStringAsFixed(1)}% (${_formatBytes(vol.capacityUsed)} / ${_formatBytes(vol.capacityTotal)})',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: vol.capacityPercent / 100.0,
                      backgroundColor: isDark ? const Color(0xFF334155) : Colors.grey[200],
                      valueColor: AlwaysStoppedAnimation<Color>(
                        vol.capacityPercent > 85 ? Colors.redAccent : const Color(0xFF10B981),
                      ),
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Bricks Table
                Text(
                  'Storage Bricks (${vol.bricks.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isDark ? const Color(0xFF334155) : Colors.grey[300]!),
                  ),
                  child: Table(
                    columnWidths: const {
                      0: FlexColumnWidth(2.5),
                      1: FlexColumnWidth(3.5),
                      2: FlexColumnWidth(1.2),
                      3: FlexColumnWidth(1.5),
                    },
                    children: [
                      TableRow(
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : Colors.grey[100],
                        ),
                        children: const [
                          Padding(padding: EdgeInsets.all(8), child: Text('CENTURION HOST', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                          Padding(padding: EdgeInsets.all(8), child: Text('BRICK STORAGE PATH', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                          Padding(padding: EdgeInsets.all(8), child: Text('PORT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                          Padding(padding: EdgeInsets.all(8), child: Text('STATUS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                        ],
                      ),
                      ...vol.bricks.map((b) {
                        return TableRow(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Row(
                                children: [
                                  const Icon(Icons.dns_outlined, size: 14, color: Color(0xFF3B82F6)),
                                  const SizedBox(width: 6),
                                  Text(b.host, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: SelectableText(b.path, style: const TextStyle(fontFamily: 'Courier New', fontSize: 11.5)),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text('${b.port}', style: const TextStyle(fontSize: 12)),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Row(
                                children: [
                                  Icon(
                                    b.online ? Icons.check_circle : Icons.error,
                                    size: 14,
                                    color: b.online ? const Color(0xFF10B981) : Colors.redAccent,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    b.online ? 'Online' : 'Offline',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: b.online ? const Color(0xFF10B981) : Colors.redAccent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Dialogs & Action Handlers for GlusterFS ───────────────────────────────

  void _showCreateGlusterVolumeDialog() {
    final nameCtrl = TextEditingController(text: 'gv_contenedores');
    final brickDirCtrl = TextEditingController(text: '/data/glusterfs/brick1');
    final mountPointCtrl = TextEditingController(text: '/var/contenedores');
    final customHostsCtrl = TextEditingController(text: '');
    int replicaCount = 3;
    bool autoMount = true;
    bool forceRecreate = false;
    String networkMode = 'storage'; // 'storage', 'management', 'custom'

    // Node selection tracking: default to first 3 nodes if >= 3, or all nodes
    final clusterNodes = widget.state.nodes;
    final Set<String> selectedNodeIds = <String>{};
    if (clusterNodes.length >= 3) {
      for (int i = 0; i < 3; i++) {
        selectedNodeIds.add(clusterNodes[i].id);
      }
      replicaCount = 3;
    } else if (clusterNodes.length == 2) {
      for (final n in clusterNodes) {
        selectedNodeIds.add(n.id);
      }
      replicaCount = 2;
    } else {
      for (final n in clusterNodes) {
        selectedNodeIds.add(n.id);
      }
      replicaCount = 2;
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            final totalSelected = selectedNodeIds.length;
            final isDivisible = totalSelected >= 2 && (totalSelected % replicaCount == 0);
            final isValid = totalSelected >= 2 && isDivisible;

            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.hub, color: Color(0xFF10B981)),
                  SizedBox(width: 8),
                  Text('Create GlusterFS Replicated Volume'),
                ],
              ),
              content: SizedBox(
                width: 620,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Volume Name',
                          hintText: 'e.g. gv_contenedores',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.folder_shared, size: 20),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Replication Strategy with clear explanation
                      DropdownButtonFormField<int>(
                        value: replicaCount,
                        decoration: const InputDecoration(
                          labelText: 'Replication Strategy (Mirror Multiplier)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.copy_all, size: 20),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 3,
                            child: Text('Replica 3 — 3-Way Mirror (Requires multiple of 3 nodes: 3, 6)'),
                          ),
                          DropdownMenuItem(
                            value: 2,
                            child: Text('Replica 2 — 2-Way Mirror (Requires multiple of 2 nodes: 2, 4)'),
                          ),
                          DropdownMenuItem(
                            value: 4,
                            child: Text('Replica 4 — 4-Way Mirror (Requires 4 nodes)'),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setDlgState(() => replicaCount = val);
                          }
                        },
                      ),
                      const SizedBox(height: 16),

                      // Storage Network Interface Selector
                      DropdownButtonFormField<String>(
                        value: networkMode,
                        decoration: const InputDecoration(
                          labelText: 'Storage Network Interface / Subnet',
                          helperText: 'Select which network GlusterFS binds its bricks and replication traffic to.',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.settings_ethernet, size: 20),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'storage',
                            child: Text('🌐 Dedicated Storage Network (Dual-NIC / 10.10.100.0/24)'),
                          ),
                          DropdownMenuItem(
                            value: 'management',
                            child: Text('🏢 Management / Primary Network (192.168.x.x)'),
                          ),
                          DropdownMenuItem(
                            value: 'custom',
                            child: Text('🛠️ Custom Host Storage IPs (Specify manually)'),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) setDlgState(() => networkMode = val);
                        },
                      ),
                      if (networkMode == 'custom') ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: customHostsCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Custom Node Storage IPs (Comma-separated)',
                            hintText: 'e.g. 10.10.100.27, 10.10.100.25, 10.10.100.26',
                            helperText: 'Enter specific storage IPs for the manager and worker bricks.',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.lan, size: 20),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),

                      // Granular Centurion Node Selection Card
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(8),
                          border: Border(
                            left: BorderSide(
                              color: isValid ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                              width: 4,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.dns, size: 18, color: Color(0xFF10B981)),
                                const SizedBox(width: 8),
                                Text(
                                  'Target Centurion Nodes ($totalSelected of ${clusterNodes.length} Selected)',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                const Spacer(),
                                // Preset Quick Select Chips
                                Wrap(
                                  spacing: 6,
                                  children: [
                                    ActionChip(
                                      visualDensity: VisualDensity.compact,
                                      avatar: const Icon(Icons.select_all, size: 14),
                                      label: const Text('All Nodes', style: TextStyle(fontSize: 11)),
                                      onPressed: () {
                                        setDlgState(() {
                                          selectedNodeIds.clear();
                                          for (final n in clusterNodes) {
                                            selectedNodeIds.add(n.id);
                                          }
                                          if (selectedNodeIds.length == 4) {
                                            replicaCount = 2; // Auto-tune 4 nodes to Replica 2
                                          } else if (selectedNodeIds.length % 3 == 0) {
                                            replicaCount = 3;
                                          }
                                        });
                                      },
                                    ),
                                    if (clusterNodes.length >= 3)
                                      ActionChip(
                                        visualDensity: VisualDensity.compact,
                                        avatar: const Icon(Icons.filter_3, size: 14),
                                        label: const Text('3 Nodes (R3)', style: TextStyle(fontSize: 11)),
                                        onPressed: () {
                                          setDlgState(() {
                                            selectedNodeIds.clear();
                                            for (int i = 0; i < 3 && i < clusterNodes.length; i++) {
                                              selectedNodeIds.add(clusterNodes[i].id);
                                            }
                                            replicaCount = 3;
                                          });
                                        },
                                      ),
                                    if (clusterNodes.length >= 2)
                                      ActionChip(
                                        visualDensity: VisualDensity.compact,
                                        avatar: const Icon(Icons.filter_2, size: 14),
                                        label: const Text('2 Nodes (R2)', style: TextStyle(fontSize: 11)),
                                        onPressed: () {
                                          setDlgState(() {
                                            selectedNodeIds.clear();
                                            for (int i = 0; i < 2 && i < clusterNodes.length; i++) {
                                              selectedNodeIds.add(clusterNodes[i].id);
                                            }
                                            replicaCount = 2;
                                          });
                                        },
                                      ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Select the physical hosts where GlusterFS will place volume bricks. The total number of selected hosts must be divisible by the replica multiplier.',
                              style: TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                            const SizedBox(height: 8),

                            // Node Checkbox List
                            ...clusterNodes.map((node) {
                              final isSelected = selectedNodeIds.contains(node.id);
                              final isMgr = node.role.toLowerCase() == 'manager';
                              return CheckboxListTile(
                                dense: true,
                                controlAffinity: ListTileControlAffinity.leading,
                                contentPadding: EdgeInsets.zero,
                                activeColor: const Color(0xFF10B981),
                                value: isSelected,
                                title: Row(
                                  children: [
                                    Icon(
                                      isMgr ? Icons.security : Icons.memory,
                                      size: 16,
                                      color: isMgr ? Colors.amber : const Color(0xFF3B82F6),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '${node.role.toUpperCase()}: ${node.labels['gbnt.node.hostname'] ?? node.id}',
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.06),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'IP: ${node.ip}',
                                        style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.grey),
                                      ),
                                    ),
                                  ],
                                ),
                                onChanged: (val) {
                                  setDlgState(() {
                                    if (val == true) {
                                      selectedNodeIds.add(node.id);
                                    } else {
                                      selectedNodeIds.remove(node.id);
                                    }
                                    // Automatic smart suggestion of replica count
                                    if (selectedNodeIds.length == 3) {
                                      replicaCount = 3;
                                    } else if (selectedNodeIds.length == 2 || selectedNodeIds.length == 4) {
                                      replicaCount = 2;
                                    }
                                  });
                                },
                              );
                            }),

                            const SizedBox(height: 8),

                            // Dynamic Validation Banner
                            if (isValid)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.check_circle, size: 16, color: Color(0xFF10B981)),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Valid Topology: $totalSelected bricks with Replica $replicaCount ($totalSelected ÷ $replicaCount = ${totalSelected ~/ replicaCount} subvolume${totalSelected ~/ replicaCount > 1 ? 's' : ''}). GlusterFS create will succeed.',
                                        style: const TextStyle(fontSize: 11, color: Color(0xFF10B981), fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEF4444).withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.3)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFEF4444)),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        totalSelected < 2
                                            ? 'Please select at least 2 Centurion nodes to form a cluster volume.'
                                            : 'Divisibility Error: $totalSelected selected nodes is not divisible by Replica $replicaCount ($totalSelected % $replicaCount = ${totalSelected % replicaCount}). Please select ${totalSelected - (totalSelected % replicaCount)} or ${(totalSelected - (totalSelected % replicaCount)) + replicaCount} nodes, or change Replica Strategy to Replica ${totalSelected == 4 ? '2' : (totalSelected % 2 == 0 ? '2' : '3')}.',
                                        style: const TextStyle(fontSize: 11, color: Color(0xFFEF4444), fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      TextField(
                        controller: brickDirCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Brick Storage Directory on Nodes',
                          hintText: 'e.g. /data/glusterfs/brick1',
                          helperText: 'Residual metadata and xattrs will be cleaned automatically.',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.storage, size: 20),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: mountPointCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Target Mount Point for Containers',
                          hintText: 'e.g. /var/contenedores',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.link, size: 20),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        title: const Text('Auto-Mount to Cluster Nodes'),
                        subtitle: const Text('Automatically writes /etc/fstab and mounts on selected nodes on creation'),
                        value: autoMount,
                        activeColor: const Color(0xFF10B981),
                        onChanged: (val) => setDlgState(() => autoMount = val),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        title: const Text('Force Recreate / Purge Ghost Volume'),
                        subtitle: const Text('If a volume with this name already exists or is in an inconsistent state, automatically stop, purge, and recreate it cleanly'),
                        value: forceRecreate,
                        activeColor: const Color(0xFF10B981),
                        onChanged: (val) => setDlgState(() => forceRecreate = val),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: isValid ? const Color(0xFF10B981) : Colors.grey,
                  ),
                  onPressed: !isValid
                      ? null
                      : () async {
                          Navigator.pop(ctx);
                          try {
                            List<String>? targetNodes;
                            if (selectedNodeIds.length == clusterNodes.length) {
                              targetNodes = ['all'];
                            } else {
                              targetNodes = selectedNodeIds.toList();
                            }
                            List<String>? customHosts;
                            if (networkMode == 'custom' && customHostsCtrl.text.trim().isNotEmpty) {
                              customHosts = customHostsCtrl.text
                                  .split(',')
                                  .map((s) => s.trim())
                                  .where((s) => s.isNotEmpty)
                                  .toList();
                            }

                            await ApiService.createGlusterVolume({
                              'name': nameCtrl.text.trim(),
                              'replica_count': replicaCount,
                              'brick_dir': brickDirCtrl.text.trim(),
                              'network_mode': networkMode,
                              'custom_hosts': customHosts,
                              'mount_point': mountPointCtrl.text.trim(),
                              'auto_mount': autoMount,
                              'target_nodes': targetNodes,
                              'force': true,
                              'force_recreate': forceRecreate,
                            });
                            _showSnackBar('GlusterFS volume ${nameCtrl.text} created and tuned successfully');
                            _loadAllData();
                          } catch (e) {
                            _showErrorDialog('Volume Creation Failed', 'Failed to create GlusterFS volume ${nameCtrl.text.trim()}:\n\n$e');
                            _showSnackBar('Failed to create volume: $e', isError: true);
                          }
                        },
                  child: const Text('Create & Optimize Volume'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showMountClusterDialog(String volumeName) {
    String selectedTarget = 'all';
    final matchingMount = _mounts.firstWhere(
      (m) => m.fsType == 'glusterfs' && (m.device.contains(volumeName) || m.name.contains(volumeName)),
      orElse: () => StorageMountModel.empty(),
    );
    final initialPath = matchingMount.mountPoint.isNotEmpty ? matchingMount.mountPoint : '/var/contenedores';
    final mountPointCtrl = TextEditingController(text: initialPath);
    bool isMounting = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.folder_shared_outlined, color: Color(0xFF10B981)),
                  const SizedBox(width: 8),
                  Text('Mount / Recreate Mount Point: $volumeName'),
                ],
              ),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (matchingMount.id.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle_outline, size: 18, color: Color(0xFF10B981)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Currently mapped to: ${matchingMount.mountPoint} (Target: ${matchingMount.targetNode})',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    TextField(
                      controller: mountPointCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Mount Directory Point',
                        hintText: '/var/contenedores',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.folder_open, size: 20),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        const Text('Quick targets: ', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        ...['/var/contenedores', '/mnt/gluster', '/data/gluster', '/var/shared'].map((p) {
                          return ActionChip(
                            label: Text(p, style: const TextStyle(fontSize: 10.5)),
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              setDlgState(() => mountPointCtrl.text = p);
                            },
                          );
                        }),
                      ],
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: selectedTarget,
                      decoration: const InputDecoration(
                        labelText: 'Target Centurion Node(s)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.computer, size: 20),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: 'all',
                          child: Text('🌐 All Centurions (Whole Cluster Mobility)'),
                        ),
                        ...widget.state.nodes.map(
                          (node) => DropdownMenuItem(
                            value: node.id,
                            child: Text('💻 ${node.role.toUpperCase()}: ${node.ip} (${node.id})'),
                          ),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) setDlgState(() => selectedTarget = val);
                      },
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Automates directory creation (0777), updates /etc/fstab, executes mount -a, and syncs cluster storage.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                  icon: isMounting
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.link, size: 16),
                  label: Text(matchingMount.id.isNotEmpty ? 'Remount / Update fstab' : 'Mount Volume to fstab'),
                  onPressed: isMounting
                      ? null
                      : () async {
                          setDlgState(() => isMounting = true);
                          try {
                            List<String>? targetNodes;
                            if (selectedTarget != 'all') {
                              targetNodes = [selectedTarget];
                            }
                            await ApiService.mountGlusterCluster(
                              volumeName,
                              mountPoint: mountPointCtrl.text.trim(),
                              targetNodes: targetNodes,
                            );
                            Navigator.pop(ctx);
                            _showSnackBar('✅ Volume $volumeName mounted successfully on target: $selectedTarget');
                            _loadAllData();
                          } catch (e) {
                            setDlgState(() => isMounting = false);
                            _showSnackBar('❌ Failed to mount volume: $e', isError: true);
                          }
                        },
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showDeleteGlusterVolumeDialog(GlusterVolumeModel vol) {
    bool unmountCluster = true;
    final matchingMount = _mounts.firstWhere(
      (m) => m.fsType == 'glusterfs' && (m.device.contains(vol.name) || m.name.contains(vol.name)),
      orElse: () => StorageMountModel.empty(),
    );
    final isMounted = vol.isMounted || matchingMount.id.isNotEmpty;
    final mountPoint = matchingMount.mountPoint.isNotEmpty ? matchingMount.mountPoint : (vol.mountPoint.isNotEmpty ? vol.mountPoint : '/var/contenedores');

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.delete_forever, color: Colors.redAccent),
                  const SizedBox(width: 8),
                  Text('Delete GlusterFS Volume: ${vol.name}'),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Are you sure you want to delete GlusterFS volume "${vol.name}" (${vol.type}, ${vol.bricks.length} bricks)?',
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    if (isMounted)
                      Container(
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.link, size: 18, color: Colors.amber),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Active Mount Point: $mountPoint across cluster hosts in /etc/fstab.',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber),
                              ),
                            ),
                          ],
                        ),
                      ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: unmountCluster,
                      activeColor: const Color(0xFF10B981),
                      title: const Text(
                        'Unmount and clean /etc/fstab across cluster nodes',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      subtitle: const Text(
                        'Safely unmounts filesystem and cleans mount entries on all Centurion hosts.',
                        style: TextStyle(fontSize: 11),
                      ),
                      onChanged: (val) => setDlgState(() => unmountCluster = val ?? true),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    try {
                      await ApiService.deleteGlusterVolume(vol.name, unmount: unmountCluster);
                      _showSnackBar('Volume ${vol.name} deleted successfully');
                      _loadAllData();
                    } catch (e) {
                      _showErrorDialog('Delete Volume Failed', 'Failed to delete volume ${vol.name}:\n\n$e');
                      _showSnackBar('Failed to delete volume: $e', isError: true);
                    }
                  },
                  child: const Text('Delete Volume'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showDeleteAllGlusterVolumesDialog() {
    bool unmountAll = true;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
                  SizedBox(width: 8),
                  Text('Delete ALL GlusterFS Volumes'),
                ],
              ),
              content: SizedBox(
                width: 500,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Are you sure you want to delete ALL ${_glusterVolumes.length} GlusterFS cluster volumes (${_glusterVolumes.map((v) => v.name).join(', ')})?',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'This action will permanently stop and remove all GlusterFS distributed volumes across all Centurion nodes.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: unmountAll,
                      activeColor: Colors.redAccent,
                      title: const Text(
                        'Unmount all GlusterFS filesystems and clean /etc/fstab across all hosts',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      subtitle: const Text(
                        'Safely unmounts and removes all GlusterFS mount records from cluster nodes.',
                        style: TextStyle(fontSize: 11),
                      ),
                      onChanged: (val) => setDlgState(() => unmountAll = val ?? true),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    try {
                      await ApiService.deleteAllGlusterVolumes(unmount: unmountAll);
                      _showSnackBar('All GlusterFS volumes deleted successfully');
                      _loadAllData();
                    } catch (e) {
                      _showSnackBar('Failed to delete all volumes: $e', isError: true);
                    }
                  },
                  child: const Text('Delete All Volumes'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showDeleteMountDialog(StorageMountModel m) {
    final isGluster = m.fsType == 'glusterfs' || m.name.contains('gluster') || m.device.contains('localhost:');
    String glusterVolName = m.name.replaceFirst('gluster-', '');
    if (m.device.startsWith('localhost:')) {
      glusterVolName = m.device.replaceFirst('localhost:', '');
    }
    bool deleteUnderlyingGluster = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(isGluster ? Icons.warning_amber_rounded : Icons.delete_outline,
                      color: isGluster ? Colors.orange : Colors.redAccent),
                  const SizedBox(width: 8),
                  Text(isGluster ? 'Delete GlusterFS Mount: ${m.name}' : 'Delete Mount Entry: ${m.name}'),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Are you sure you want to delete mount "${m.name}" (${m.mountPoint}) on target hosts (${m.targetNode})?\n\nThis will unmount the filesystem and remove its entry from /etc/fstab.',
                      style: const TextStyle(fontSize: 13),
                    ),
                    if (isGluster) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                        ),
                        child: CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: deleteUnderlyingGluster,
                          activeColor: Colors.redAccent,
                          title: Text(
                            'Also permanently STOP & DELETE underlying GlusterFS volume "$glusterVolName"',
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.redAccent),
                          ),
                          subtitle: const Text(
                            'If unchecked, the volume stays intact in GlusterFS and only the fstab mount point is unmounted and removed.',
                            style: TextStyle(fontSize: 11),
                          ),
                          onChanged: (val) => setDlgState(() => deleteUnderlyingGluster = val ?? false),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    try {
                      await ApiService.deleteStorageMount(m.id, deleteGluster: deleteUnderlyingGluster);
                      _showSnackBar(deleteUnderlyingGluster
                          ? 'Mount and GlusterFS volume "$glusterVolName" deleted successfully'
                          : 'Mount removed from fstab');
                      _loadAllData();
                    } catch (e) {
                      _showSnackBar('Failed to delete mount: $e', isError: true);
                    }
                  },
                  child: const Text('Delete'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showProbePeerDialog() {
    final hostCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.person_add, color: Color(0xFF3B82F6)),
              SizedBox(width: 8),
              Text('Probe GlusterFS Peer Node'),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: TextField(
              controller: hostCtrl,
              decoration: const InputDecoration(
                labelText: 'Target Node IP or Hostname',
                hintText: 'e.g. 192.168.252.28',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF3B82F6)),
              onPressed: () async {
                final host = hostCtrl.text.trim();
                if (host.isEmpty) return;
                Navigator.pop(ctx);
                try {
                  await ApiService.probeGlusterPeer(host);
                  _showSnackBar('Successfully probed peer $host');
                  _loadAllData();
                } catch (e) {
                  _showSnackBar('Failed to probe peer: $e', isError: true);
                }
              },
              child: const Text('Probe Peer'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showGlusterHealDialog(String volumeName) async {
    try {
      final report = await ApiService.fetchGlusterHealReport(volumeName);
      if (!mounted) return;

      showDialog(
        context: context,
        builder: (ctx) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.medical_services_outlined, color: Color(0xFF10B981)),
                const SizedBox(width: 8),
                Text('Self-Heal Diagnostics: $volumeName'),
              ],
            ),
            content: SizedBox(
              width: 550,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: report.inSplitBrain
                          ? Colors.redAccent.withValues(alpha: 0.15)
                          : const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: report.inSplitBrain ? Colors.redAccent : const Color(0xFF10B981),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          report.inSplitBrain ? Icons.error : Icons.check_circle,
                          color: report.inSplitBrain ? Colors.redAccent : const Color(0xFF10B981),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                report.statusSummary,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Pending files to heal: ${report.totalPending} | Split-Brain: ${report.inSplitBrain ? "YES" : "NO"}',
                                style: TextStyle(fontSize: 11.5, color: isDark ? Colors.grey[300] : Colors.grey[700]),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Brick Health & Entry Queue:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  if (report.bricksHealInfo.isEmpty)
                    const Text('All 3 bricks report 0 pending entries (100% in sync).')
                  else
                    ...report.bricksHealInfo.map((b) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.dns, size: 14, color: Color(0xFF3B82F6)),
                            const SizedBox(width: 6),
                            Expanded(child: Text(b.brickSpec, style: const TextStyle(fontSize: 12, fontFamily: 'Courier New'))),
                            Text('${b.numberOfEntries} pending', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
            actions: [
              OutlinedButton.icon(
                icon: const Icon(Icons.healing, size: 16),
                label: const Text('Trigger Self-Heal Now'),
                onPressed: () async {
                  try {
                    await ApiService.triggerGlusterSelfHeal(volumeName);
                    _showSnackBar('Self-heal cycle initiated for $volumeName');
                    Navigator.pop(ctx);
                  } catch (e) {
                    _showSnackBar('Failed to trigger self-heal: $e', isError: true);
                  }
                },
              ),
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
            ],
          );
        },
      );
    } catch (e) {
      _showSnackBar('Failed to fetch heal report: $e', isError: true);
    }
  }

  Future<void> _startGlusterVolume(String name) async {
    try {
      await ApiService.startGlusterVolume(name);
      _showSnackBar('Volume $name started');
      _loadAllData();
    } catch (e) {
      _showErrorDialog('Start Volume Failed', 'Failed to start volume $name:\n\n$e');
      _showSnackBar('Failed to start volume: $e', isError: true);
    }
  }

  Future<void> _stopGlusterVolume(String name) async {
    try {
      await ApiService.stopGlusterVolume(name, force: true);
      _showSnackBar('Volume $name stopped');
      _loadAllData();
    } catch (e) {
      _showErrorDialog('Stop Volume Failed', 'Failed to stop volume $name:\n\n$e');
      _showSnackBar('Failed to stop volume: $e', isError: true);
    }
  }

  Future<void> _mountGlusterCluster(String name) async {
    try {
      await ApiService.mountGlusterCluster(name, mountPoint: '/var/contenedores');
      _showSnackBar('Volume $name registered and mounted on /var/contenedores across cluster');
      _loadAllData();
    } catch (e) {
      _showErrorDialog('Mount Volume Failed', 'Failed to mount volume $name:\n\n$e');
      _showSnackBar('Failed to mount volume: $e', isError: true);
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = (bytes > 0) ? (bytes.bitLength - 1) ~/ 10 : 0;
    if (i >= suffixes.length) i = suffixes.length - 1;
    double count = bytes / (1 << (i * 10));
    return '${count.toStringAsFixed(1)} ${suffixes[i]}';
  }
}



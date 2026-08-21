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
  bool _loading = false;

  // Filters
  String _volumeSearch = '';
  String _volumeTypeFilter = 'ALL';
  String _backupSearch = '';
  String _mountSearch = '';
  String _mountTypeFilter = 'ALL';
  String _poolPath = '/var/contenedores';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
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
      final volsFuture = ApiService.fetchStorageVolumes();
      final backupsFuture = ApiService.fetchBackups();
      final schedulesFuture = ApiService.fetchBackupSchedules();
      final healthFuture = ApiService.fetchStoragePoolHealth(path: _poolPath);
      final mountsFuture = ApiService.fetchStorageMounts();

      final results = await Future.wait([
        volsFuture.catchError((_) => <StorageVolumeModel>[]),
        backupsFuture.catchError((_) => <BackupModel>[]),
        schedulesFuture.catchError((_) => <BackupScheduleModel>[]),
        healthFuture.catchError((_) => PoolHealthModel(poolPath: _poolPath, status: 'error')),
        mountsFuture.catchError((_) => <StorageMountModel>[]),
      ]);

      if (mounted) {
        setState(() {
          _volumes = results[0] as List<StorageVolumeModel>;
          _backups = results[1] as List<BackupModel>;
          _schedules = results[2] as List<BackupScheduleModel>;
          _poolHealth = results[3] as PoolHealthModel;
          _mounts = results[4] as List<StorageMountModel>;
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
        duration: const Duration(seconds: 3),
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

  void _showCreateBackupDialog({String? initialStackId, String? initialVolumeName, String? initialSourcePath}) {
    final nameCtrl = TextEditingController(text: initialVolumeName != null ? 'backup-$initialVolumeName' : '');
    final sourcePathCtrl = TextEditingController(text: initialSourcePath ?? '');
    String selectedStack = initialStackId ?? (widget.state.stacks.isNotEmpty ? widget.state.stacks.first.id : '');
    bool pauseContainer = true;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.backup, color: Color(0xFF10B981)),
                  SizedBox(width: 8),
                  Text('Create Compressed Backup'),
                ],
              ),
              content: SizedBox(
                width: 500,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Backup Name',
                        hintText: 'e.g. backup-wordpress-db',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (widget.state.stacks.isNotEmpty) ...[
                      DropdownButtonFormField<String>(
                        value: selectedStack.isNotEmpty ? selectedStack : null,
                        decoration: const InputDecoration(
                          labelText: 'Associated Stack (Legion)',
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
                            setDlgState(() => selectedStack = val);
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextField(
                      controller: sourcePathCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Source Directory / Volume Path',
                        hintText: 'e.g. /var/contenedores/wordpress/data',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
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
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                FilledButton.icon(
                  icon: const Icon(Icons.archive, size: 18),
                  label: const Text('Create Backup'),
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    try {
                      _showSnackBar('Creating backup archive...');
                      await ApiService.createBackup(
                        name: nameCtrl.text.trim(),
                        stackId: selectedStack,
                        volumeName: initialVolumeName ?? '',
                        sourcePath: sourcePathCtrl.text.trim(),
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

  void _showRestoreDialog(BackupModel backup) {
    final targetCtrl = TextEditingController(text: backup.sourcePath);

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.restore, color: Color(0xFF3B82F6)),
              SizedBox(width: 8),
              Text('Restore Backup Archive'),
            ],
          ),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('You are about to restore backup "${backup.name}" (${backup.sizeFormatted}).', style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 16),
                TextField(
                  controller: targetCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Target Restore Directory',
                    hintText: 'e.g. /var/contenedores/wordpress/data',
                    border: OutlineInputBorder(),
                  ),
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
  }

  void _showScheduleDialog({BackupScheduleModel? schedule}) {
    final nameCtrl = TextEditingController(text: schedule?.name ?? '');
    final cronCtrl = TextEditingController(text: schedule?.cronExpression ?? '0 3 * * *');
    String selectedStack = schedule?.targetId ?? (widget.state.stacks.isNotEmpty ? widget.state.stacks.first.id : '');
    int retention = schedule?.retentionCount ?? 7;
    bool pauseContainers = schedule?.pauseContainers ?? true;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.schedule, color: Color(0xFF8B5CF6)),
                  const SizedBox(width: 8),
                  Text(schedule == null ? 'New Backup Schedule' : 'Edit Backup Schedule'),
                ],
              ),
              content: SizedBox(
                width: 500,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Policy Name',
                        hintText: 'e.g. Daily WordPress DB Backup',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (widget.state.stacks.isNotEmpty) ...[
                      DropdownButtonFormField<String>(
                        value: selectedStack.isNotEmpty ? selectedStack : null,
                        decoration: const InputDecoration(
                          labelText: 'Target Stack (Legion)',
                          border: OutlineInputBorder(),
                        ),
                        items: widget.state.stacks.map((s) {
                          return DropdownMenuItem(
                            value: s.id,
                            child: Text('${s.name} (${s.id})'),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setDlgState(() => selectedStack = val);
                        },
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextField(
                      controller: cronCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Cron Expression',
                        hintText: 'e.g. 0 3 * * * (Daily at 03:00 AM)',
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
                          label: const Text('Weekly (Sun)', style: TextStyle(fontSize: 11)),
                          onPressed: () => setDlgState(() => cronCtrl.text = '0 3 * * 0'),
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
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6)),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    try {
                      final item = BackupScheduleModel(
                        id: schedule?.id ?? '',
                        name: nameCtrl.text.trim(),
                        cronExpression: cronCtrl.text.trim(),
                        targetType: 'stack',
                        targetId: selectedStack,
                        targetName: selectedStack,
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
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.grey[200],
                borderRadius: BorderRadius.circular(10),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: const Color(0xFF10B981),
                ),
                labelColor: Colors.white,
                unselectedLabelColor: isDark ? Colors.grey[400] : Colors.grey[700],
                tabs: [
                  Tab(
                    icon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.inventory_2_outlined, size: 18),
                        const SizedBox(width: 6),
                        Text('Volumes (${_volumes.length})'),
                      ],
                    ),
                  ),
                  Tab(
                    icon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.backup_outlined, size: 18),
                        const SizedBox(width: 6),
                        Text('Backups & Snapshots (${_backups.length})'),
                      ],
                    ),
                  ),
                  Tab(
                    icon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.schedule_outlined, size: 18),
                        const SizedBox(width: 6),
                        Text('Schedules (${_schedules.length})'),
                      ],
                    ),
                  ),
                  const Tab(
                    icon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.folder_shared_outlined, size: 18),
                        SizedBox(width: 6),
                        Text('Storage Pools'),
                      ],
                    ),
                  ),
                  Tab(
                    icon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.dns_outlined, size: 18),
                        const SizedBox(width: 6),
                        Text('Network Mounts & fstab (${_mounts.length})'),
                      ],
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
          v.sourcePath.toLowerCase().contains(_volumeSearch.toLowerCase());
      final matchesType = _volumeTypeFilter == 'ALL' || v.type == _volumeTypeFilter;
      return matchesSearch && matchesType;
    }).toList();

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search volumes by name, stack, or source path...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1E293B) : Colors.grey[100],
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                ),
                onChanged: (val) => setState(() => _volumeSearch = val),
              ),
            ),
            const SizedBox(width: 12),
            DropdownButton<String>(
              value: _volumeTypeFilter,
              items: const [
                DropdownMenuItem(value: 'ALL', child: Text('All Types')),
                DropdownMenuItem(value: 'shared_pool', child: Text('Shared Pool (/var/contenedores)')),
                DropdownMenuItem(value: 'docker_named', child: Text('Docker Named Volumes')),
                DropdownMenuItem(value: 'host_bind', child: Text('Host Bind Mounts')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _volumeTypeFilter = val);
              },
            ),
          ],
        ),
        const SizedBox(height: 14),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    'No volumes found matching the criteria.',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                )
              : ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (ctx, i) {
                    final v = filtered[i];
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
                                    : Colors.blueAccent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                v.isShared ? Icons.cloud_done : Icons.storage,
                                color: v.isShared ? const Color(0xFF10B981) : Colors.blueAccent,
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
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: v.isShared
                                              ? const Color(0xFF10B981).withValues(alpha: 0.2)
                                              : Colors.grey.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          v.type.toUpperCase().replaceAll('_', ' '),
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: v.isShared ? const Color(0xFF10B981) : Colors.grey[400],
                                          ),
                                        ),
                                      ),
                                      if (v.isShared) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.amber.withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: const Text(
                                            'SHARED POOL',
                                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Stack: ${v.stackName.isNotEmpty ? v.stackName : "Standalone"} | Source: ${v.sourcePath} ➔ Target: ${v.targetPath.isNotEmpty ? v.targetPath : v.sourcePath}',
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
                            const SizedBox(width: 12),
                            FilledButton.icon(
                              icon: const Icon(Icons.camera_alt, size: 16),
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
              OutlinedButton.icon(
                icon: const Icon(Icons.code, size: 16),
                label: const Text('View /etc/fstab'),
                onPressed: _showFstabViewerDialog,
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.sync, size: 16),
                label: const Text('Mount All (mount -a)'),
                onPressed: () async {
                  try {
                    _showSnackBar('Executing mount -a on host...');
                    await ApiService.mountAllStorageEntries();
                    _showSnackBar('✅ mount -a executed successfully');
                    _loadAllData();
                  } catch (e) {
                    _showSnackBar('❌ mount -a failed: $e', isError: true);
                  }
                },
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
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Delete Mount Entry'),
                                    content: Text('Are you sure you want to delete mount "${m.name}" (${m.mountPoint})?\n\nThis will unmount the filesystem and remove its entry from /etc/fstab.'),
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
                                    await ApiService.deleteStorageMount(m.id);
                                    _showSnackBar('Mount deleted successfully');
                                    _loadAllData();
                                  } catch (e) {
                                    _showSnackBar('Failed to delete mount: $e', isError: true);
                                  }
                                }
                              },
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
                          ButtonSegment(value: 'cifs', label: Text('Samba / CIFS'), icon: Icon(Icons.folder_shared, size: 16)),
                          ButtonSegment(value: 's3', label: Text('S3 Object'), icon: Icon(Icons.cloud_queue, size: 16)),
                          ButtonSegment(value: 'custom', label: Text('Custom / POSIX'), icon: Icon(Icons.settings, size: 16)),
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

  void _showFstabViewerDialog() async {
    try {
      final fstabData = await ApiService.fetchRawFstab();
      final path = fstabData['path'] ?? '/etc/fstab';
      final rawContent = fstabData['raw'] ?? '';

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (ctx) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.code, color: Color(0xFF3B82F6)),
                const SizedBox(width: 8),
                Text('Host Configuration: $path'),
              ],
            ),
            content: SizedBox(
              width: 650,
              height: 400,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isDark ? const Color(0xFF334155) : Colors.grey[300]!),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    rawContent,
                    style: TextStyle(
                      fontFamily: 'Courier New',
                      fontSize: 12.5,
                      color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B),
                    ),
                  ),
                ),
              ),
            ),
            actions: [
              OutlinedButton.icon(
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy to Clipboard'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: rawContent));
                  _showSnackBar('Copied /etc/fstab content to clipboard');
                },
              ),
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
            ],
          );
        },
      );
    } catch (e) {
      _showSnackBar('Failed to read /etc/fstab: $e', isError: true);
    }
  }
}


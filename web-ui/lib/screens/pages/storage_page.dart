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
  PoolHealthModel? _poolHealth;
  bool _loading = false;

  // Filters
  String _volumeSearch = '';
  String _volumeTypeFilter = 'ALL';
  String _backupSearch = '';
  String _poolPath = '/var/contenedores';

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
      final volsFuture = ApiService.fetchStorageVolumes();
      final backupsFuture = ApiService.fetchBackups();
      final schedulesFuture = ApiService.fetchBackupSchedules();
      final healthFuture = ApiService.fetchStoragePoolHealth(path: _poolPath);

      final results = await Future.wait([
        volsFuture.catchError((_) => <StorageVolumeModel>[]),
        backupsFuture.catchError((_) => <BackupModel>[]),
        schedulesFuture.catchError((_) => <BackupScheduleModel>[]),
        healthFuture.catchError((_) => PoolHealthModel(poolPath: _poolPath, status: 'error')),
      ]);

      if (mounted) {
        setState(() {
          _volumes = results[0] as List<StorageVolumeModel>;
          _backups = results[1] as List<BackupModel>;
          _schedules = results[2] as List<BackupScheduleModel>;
          _poolHealth = results[3] as PoolHealthModel;
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
}

import 'package:flutter/material.dart';
import '../models/models.dart' as models;
import '../services/api_service.dart';

/// Modal dialog displaying the Gubernator Built-in POC Examples & Blueprints Library.
class POCExamplesDialog extends StatefulWidget {
  final List<models.Node> nodes;
  final Function(String name, String yaml)? onOpenInStudio;
  final VoidCallback? onStackDeployed;

  const POCExamplesDialog({
    super.key,
    required this.nodes,
    this.onOpenInStudio,
    this.onStackDeployed,
  });

  @override
  State<POCExamplesDialog> createState() => _POCExamplesDialogState();
}

class _POCExamplesDialogState extends State<POCExamplesDialog> {
  bool _loading = true;
  String? _error;
  List<models.POCExampleModel> _examples = [];
  String _selectedCategory = 'All';
  String _selectedNode = 'auto';
  String? _deployingId;
  bool _deployingAll = false;
  int _activeTab = 0; // 0 = POC Catalog, 1 = Master Server Guide

  @override
  void initState() {
    super.initState();
    _loadExamples();
  }

  Future<void> _loadExamples() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final list = await ApiService.fetchPOCExamples();
      setState(() {
        _examples = list;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _deployExample(models.POCExampleModel ex) async {
    setState(() => _deployingId = ex.id);

    try {
      final err = await ApiService.deployPOCExample(ex.id, targetNode: _selectedNode);
      if (mounted) {
        setState(() => _deployingId = null);
        if (err == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🚀 POC Example "${ex.name}" deployed successfully as stack "${ex.defaultStack}"!'),
              backgroundColor: const Color(0xFF238636),
            ),
          );
          widget.onStackDeployed?.call();
          Navigator.pop(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to deploy: $err'), backgroundColor: Colors.redAccent),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _deployingId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _deployAllExamples() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('Deploy All POC Blueprints?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will deploy all 8 production POC example stacks into your Gubernator cluster for proof-of-concept testing and demonstration.\n\nAre you sure you want to proceed?',
          style: TextStyle(color: Color(0xFFC9D1D9)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF238636)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Deploy All POCs'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _deployingAll = true);

    try {
      final err = await ApiService.deployPOCExample('all', targetNode: _selectedNode);
      if (mounted) {
        setState(() => _deployingAll = false);
        if (err == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🚀 All POC examples deployed successfully into the cluster!'),
              backgroundColor: Color(0xFF238636),
            ),
          );
          widget.onStackDeployed?.call();
          Navigator.pop(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Warning: $err'), backgroundColor: Colors.orangeAccent),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _deployingAll = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  IconData _resolveIcon(String iconName) {
    switch (iconName) {
      case 'compare_arrows':
        return Icons.compare_arrows;
      case 'web':
        return Icons.web;
      case 'lock':
        return Icons.lock_outline;
      case 'speed':
        return Icons.speed;
      case 'account_tree':
        return Icons.account_tree_outlined;
      case 'timeline':
        return Icons.timeline;
      case 'science':
        return Icons.science_outlined;
      case 'monitor_heart':
        return Icons.monitor_heart_outlined;
      default:
        return Icons.rocket_launch;
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ['All', 'Web & Ingress', 'Database & CMS', 'SRE & Observability', 'Automation & AI', 'AI & Data Science'];
    final filtered = _examples.where((ex) {
      if (_selectedCategory == 'All') return true;
      return ex.category == _selectedCategory;
    }).toList();

    return Dialog(
      backgroundColor: const Color(0xFF161B22),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF30363D)),
      ),
      child: Container(
        width: 1050,
        height: 720,
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Bar
            Row(
              children: [
                const Icon(Icons.rocket_launch, color: Color(0xFFE3B341), size: 26),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Gubernator POC Examples & Server Stacks Library',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    Text(
                      'Production-ready blueprints bundled with Gubernator to test clustering, ingress, volumes, and SLOs',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
                const Spacer(),
                // Tab switcher
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1117),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF30363D)),
                  ),
                  child: Row(
                    children: [
                      _tabHeaderButton('🏛️ Blueprints Catalog', 0),
                      _tabHeaderButton('📖 Master Server Guide', 1),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Tab 0: POC Catalog
            if (_activeTab == 0) ...[
              // Toolbar: Category filters + Target node + Deploy All button
              Row(
                children: [
                  // Category chips
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: categories.map((cat) {
                          final isSelected = _selectedCategory == cat;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: FilterChip(
                              label: Text(cat),
                              selected: isSelected,
                              selectedColor: const Color(0xFF1F6FEB).withOpacity(0.3),
                              checkmarkColor: const Color(0xFF58A6FF),
                              backgroundColor: const Color(0xFF0D1117),
                              side: BorderSide(
                                color: isSelected ? const Color(0xFF58A6FF) : const Color(0xFF30363D),
                              ),
                              labelStyle: TextStyle(
                                fontSize: 12,
                                color: isSelected ? Colors.white : const Color(0xFF8B949E),
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                              onSelected: (_) => setState(() => _selectedCategory = cat),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Target node dropdown
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D1117),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF30363D)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedNode,
                        dropdownColor: const Color(0xFF161B22),
                        style: const TextStyle(fontSize: 12, color: Colors.white),
                        icon: const Icon(Icons.arrow_drop_down, color: Colors.grey, size: 20),
                        items: [
                          const DropdownMenuItem(value: 'auto', child: Text('Placement: Auto (Scheduler)')),
                          ...widget.nodes.map((n) => DropdownMenuItem(
                                value: n.id,
                                child: Text('Node: ${n.id} (${n.ip})'),
                              )),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedNode = val);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Deploy All POCs Button
                  ElevatedButton.icon(
                    icon: _deployingAll
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.flash_on, size: 16),
                    label: const Text('Deploy All POCs'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF238636),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    onPressed: _deployingAll || _loading ? null : _deployAllExamples,
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Grid of POC Cards
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)))
                        : GridView.builder(
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 14,
                              mainAxisSpacing: 14,
                              childAspectRatio: 2.1,
                            ),
                            itemCount: filtered.length,
                            itemBuilder: (context, idx) {
                              final ex = filtered[idx];
                              final isDeploying = _deployingId == ex.id;
                              return _buildPOCCard(ex, isDeploying);
                            },
                          ),
              ),
            ] else ...[
              // Tab 1: Master Server Guide
              Expanded(child: _buildMasterServerGuide()),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tabHeaderButton(String label, int tabIdx) {
    final isSelected = _activeTab == tabIdx;
    return InkWell(
      onTap: () => setState(() => _activeTab = tabIdx),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1F6FEB) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.white : Colors.grey,
          ),
        ),
      ),
    );
  }

  Widget _buildPOCCard(models.POCExampleModel ex, bool isDeploying) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card Header: Icon + Name + Category badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF161B22),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF30363D)),
                ),
                child: Icon(_resolveIcon(ex.icon), color: const Color(0xFF58A6FF), size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ex.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF30363D),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            ex.category,
                            style: const TextStyle(fontSize: 10, color: Color(0xFF8B949E), fontWeight: FontWeight.w500),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Stack: ${ex.defaultStack}',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF58A6FF), fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Description
          Expanded(
            child: Text(
              ex.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Color(0xFF8B949E), height: 1.3),
            ),
          ),
          const SizedBox(height: 6),

          // Service chips & actions
          Row(
            children: [
              // Services indicator
              ...ex.services.map((s) => Container(
                    margin: const EdgeInsets.only(right: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F6FEB).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF1F6FEB).withOpacity(0.4)),
                    ),
                    child: Text(
                      s,
                      style: const TextStyle(fontSize: 10, color: Color(0xFF58A6FF), fontFamily: 'monospace'),
                    ),
                  )),
              const Spacer(),

              // Open in Studio Button
              if (widget.onOpenInStudio != null)
                TextButton.icon(
                  icon: const Icon(Icons.edit_document, size: 14, color: Colors.grey),
                  label: const Text('Studio', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                  onPressed: isDeploying
                      ? null
                      : () {
                          widget.onOpenInStudio!(ex.defaultStack, ex.composeRaw);
                          Navigator.pop(context);
                        },
                ),
              const SizedBox(width: 6),

              // Deploy Button
              ElevatedButton.icon(
                icon: isDeploying
                    ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.rocket_launch, size: 14),
                label: Text(isDeploying ? 'Deploying...' : 'Deploy POC'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1F6FEB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
                onPressed: isDeploying ? null : () => _deployExample(ex),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMasterServerGuide() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.menu_book, color: Color(0xFF58A6FF), size: 22),
                SizedBox(width: 8),
                Text(
                  'Guide: Loading Stacks from Master Server & Auto-Deploying POCs',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _guideSection(
              title: '1. Why Load Stacks from the Master Server?',
              content:
                  'Previously, stacks had to be uploaded from your local workstation browser. Now, Gubernator allows deploying Docker Compose files stored directly on the Master server filesystem (e.g. ~/.gbnt/stacks/ or /etc/gubernator/stacks/). This enables GitOps pipelines, automated cron syncs, and local server management without needing local file transfers.',
            ),
            _guideSection(
              title: '2. Default Stacks Directory on Master Host',
              content:
                  'Drop any standard Docker Compose files (.yml or .yaml) on the Master server at:\n\n'
                  '  • ~/.gbnt/stacks/  (User stacks directory)\n'
                  '  • ~/.gbnt/examples/ (Bundled POC blueprints)\n'
                  '  • /etc/gubernator/stacks/ (System-wide stacks)\n\n'
                  'To list files from the CLI: gbnt stack server-ls\n'
                  'To deploy a server file: gbnt stack deploy --from-server ~/.gbnt/stacks/my-app.yml',
            ),
            _guideSection(
              title: '3. Deploying POC Examples During Cluster Installation',
              content:
                  'You can automatically provision all 8 POC examples when bootstrapping a new cluster:\n\n'
                  '  Option A (CLI): gbnt legion init --with-examples\n'
                  '  Option B (Environment Variable): GBNT_DEPLOY_EXAMPLES=true gbnt serve\n'
                  '  Option C (One-click in Dashboard): Click "Deploy All POCs" in this dialog!\n\n'
                  'The orchestrator will automatically create the stacks, register CoreDNS records, setup Caddy ingress, and assign replicas across Centurion worker nodes.',
            ),
            _guideSection(
              title: '4. Full CLI Parity Commands',
              content:
                  '  • gbnt examples ls                    List all built-in POC blueprints\n'
                  '  • gbnt examples deploy <id|all>       Deploy one or all POC examples\n'
                  '  • gbnt stack server-ls                List Compose files found on Master host\n'
                  '  • gbnt stack deploy --from-server <p> Deploy a stack from the Master server filesystem',
            ),
          ],
        ),
      ),
    );
  }

  Widget _guideSection({required String title, required String content}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF58A6FF))),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF30363D)),
            ),
            child: Text(
              content,
              style: const TextStyle(fontSize: 12, color: Color(0xFFC9D1D9), height: 1.4, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }
}

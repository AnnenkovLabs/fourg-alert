/// Offline maps download screen — by oblast or route.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fourg_alert/services/offline_tiles.dart';

class OfflineMapsScreen extends StatefulWidget {
  final OfflineTileManager manager;

  const OfflineMapsScreen({super.key, required this.manager});

  @override
  State<OfflineMapsScreen> createState() => _OfflineMapsScreenState();
}

class _OfflineMapsScreenState extends State<OfflineMapsScreen> {
  final _activeProgress = <String, DownloadProgress>{};
  Timer? _refreshTimer;
  String? _expandedOblast;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _startOblastDownload(Oblast oblast) async {
    final estSize = widget.manager.estimateOblastSize(oblast);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Download ${oblast.name}'),
        content: Text(
          'Estimated size: ~$estSize MB\n'
          'Zooms 7–14\n'
          'Tiles will be downloaded from OpenStreetMap.\n\n'
          'Continue?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Download')),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _expandedOblast = null);
    final progress = await widget.manager.downloadOblast(oblast);
    setState(() => _activeProgress[progress.id] = progress);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline Maps'),
        backgroundColor: Colors.black,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Active downloads section
          if (_activeProgress.isNotEmpty) ...[
            const Text('Active Downloads',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF00C853))),
            const SizedBox(height: 8),
            ..._activeProgress.values.map(_buildProgressTile),
            const Divider(height: 32),
          ],

          const Text('Download by Oblast',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF00C853))),
          const SizedBox(height: 4),
          const Text('Select a region to download offline map tiles.',
              style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 12),

          ...oblasts.map((o) => _oblastTile(o)),

          const SizedBox(height: 16),
          const Text(
            'Note: OpenStreetMap tiles are free. Please be respectful — '
            'download only what you need. Large oblasts may take several minutes.',
            style: TextStyle(color: Colors.grey, fontSize: 11),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _oblastTile(Oblast oblast) {
    final estSize = widget.manager.estimateOblastSize(oblast);
    final expanded = _expandedOblast == oblast.name;

    return Card(
      color: Colors.white.withValues(alpha: 0.04),
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.map, color: Colors.white54),
            title: Text(oblast.name),
            subtitle: Text('~$estSize MB · zoom 7–14',
                style: const TextStyle(fontSize: 11)),
            trailing: const Icon(Icons.download, color: Color(0xFF00C853)),
            onTap: () => setState(() => _expandedOblast = expanded ? null : oblast.name),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _startOblastDownload(oblast),
                      icon: const Icon(Icons.download, size: 18),
                      label: const Text('Download'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF00C853),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProgressTile(DownloadProgress p) {
    return Card(
      color: Colors.white.withValues(alpha: 0.05),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: p.isComplete
            ? const Icon(Icons.check_circle, color: Color(0xFF00C853))
            : p.isError
                ? const Icon(Icons.error, color: Colors.red)
                : const SizedBox(
                    width: 24, height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00C853)),
                  ),
        title: Text(p.label, style: const TextStyle(fontSize: 13)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: p.progress,
              color: const Color(0xFF00C853),
              backgroundColor: Colors.white10,
            ),
            const SizedBox(height: 2),
            Text('${p.downloadedTiles}/${p.totalTiles} tiles',
                style: const TextStyle(fontSize: 10)),
          ],
        ),
        trailing: p.isComplete || p.isError
            ? IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: () {
                  widget.manager.cancel(p.id);
                  setState(() => _activeProgress.remove(p.id));
                },
              )
            : null,
      ),
    );
  }
}

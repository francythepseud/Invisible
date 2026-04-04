import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:invisible/core/services/call_log_service.dart';
import 'package:invisible/models/call_log_entry.dart';
import 'package:invisible/utils/constants.dart';

/// Registro chiamate: lista cronologica con eliminazione singola o totale.
class CallsListScreen extends StatefulWidget {
  const CallsListScreen({super.key});

  @override
  State<CallsListScreen> createState() => _CallsListScreenState();
}

enum _CallFilter { all, incoming, outgoing }

class _CallsListScreenState extends State<CallsListScreen> {
  final _logService = CallLogService();
  List<CallLogEntry> _entries = [];
  bool _isLoading = true;
  _CallFilter _filter = _CallFilter.all;

  List<CallLogEntry> get _filtered {
    switch (_filter) {
      case _CallFilter.all:
        return _entries;
      case _CallFilter.incoming:
        return _entries.where((e) => e.direction == CallDirection.incoming).toList();
      case _CallFilter.outgoing:
        return _entries.where((e) => e.direction == CallDirection.outgoing).toList();
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await _logService.getEntries();
    if (mounted) setState(() { _entries = entries; _isLoading = false; });
  }

  Future<void> _deleteEntry(CallLogEntry entry) async {
    await _logService.deleteEntry(entry.id);
    setState(() => _entries.removeWhere((e) => e.id == entry.id));
  }

  Future<void> _clearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppConstants.surfaceBlack,
        title: const Text('Cancella registro'),
        content: const Text('Eliminare tutta la cronologia delle chiamate?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppConstants.error),
            child: const Text('Cancella tutto'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _logService.clearAll();
      if (mounted) setState(() => _entries.clear());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.backgroundBlack,
      appBar: AppBar(
        title: const Text('Chiamate'),
        actions: [
          if (_entries.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded),
              tooltip: 'Cancella tutto',
              onPressed: _clearAll,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildFilterBar(),
                Expanded(
                  child: _filtered.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          onRefresh: _load,
                          color: AppConstants.primaryBlue,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: _filtered.length,
                            itemBuilder: (_, i) => _buildItem(_filtered[i]),
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      color: AppConstants.surfaceBlack,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _filterChip(_CallFilter.all, 'Tutte'),
          const SizedBox(width: 8),
          _filterChip(_CallFilter.incoming, 'In entrata'),
          const SizedBox(width: 8),
          _filterChip(_CallFilter.outgoing, 'In uscita'),
        ],
      ),
    );
  }

  Widget _filterChip(_CallFilter value, String label) {
    final active = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? AppConstants.primaryBlue.withValues(alpha: 0.18)
              : AppConstants.cardBlack,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active
                ? AppConstants.primaryBlue
                : AppConstants.divider.withValues(alpha: 0.4),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: active ? AppConstants.primaryBlue : AppConstants.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.phone_missed_rounded,
            size: 72,
            color: AppConstants.textTertiary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          const Text(
            'Nessuna chiamata',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppConstants.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'La cronologia apparirà qui',
            style: TextStyle(fontSize: 13, color: AppConstants.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(CallLogEntry entry) {
    return Dismissible(
      key: Key(entry.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: AppConstants.error.withValues(alpha: 0.15),
        child: const Icon(Icons.delete_outline_rounded,
            color: AppConstants.error, size: 26),
      ),
      onDismissed: (_) => _deleteEntry(entry),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: _buildLeadingIcon(entry),
        title: Text(
          entry.contactName,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: AppConstants.textPrimary,
          ),
        ),
        subtitle: Text(
          _buildSubtitle(entry),
          style: TextStyle(
            fontSize: 12,
            color: entry.status == CallStatus.missed
                ? AppConstants.error
                : AppConstants.textTertiary,
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _formatDate(entry.startedAt),
              style: const TextStyle(
                fontSize: 11,
                color: AppConstants.textTertiary,
              ),
            ),
            const SizedBox(height: 3),
            if (entry.status == CallStatus.completed &&
                entry.durationSeconds > 0)
              Text(
                _formatDuration(entry.durationSeconds),
                style: const TextStyle(
                  fontSize: 11,
                  color: AppConstants.textTertiary,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeadingIcon(CallLogEntry entry) {
    final isVideo = entry.callType == CallType.video;
    final isOut = entry.direction == CallDirection.outgoing;
    final isMissed = entry.status == CallStatus.missed;
    final isRejected = entry.status == CallStatus.rejected;

    Color iconColor;
    if (isMissed || isRejected) {
      iconColor = AppConstants.error;
    } else if (isOut) {
      iconColor = AppConstants.primaryBlue;
    } else {
      iconColor = AppConstants.success;
    }

    final arrowIcon = isOut
        ? Icons.call_made_rounded
        : (isMissed ? Icons.call_missed_rounded : Icons.call_received_rounded);

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: iconColor.withValues(alpha: 0.12),
      ),
      child: Stack(
        children: [
          Center(
            child: Icon(
              isVideo ? Icons.videocam_rounded : Icons.call_rounded,
              color: iconColor,
              size: 20,
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppConstants.backgroundBlack,
              ),
              child: Icon(arrowIcon, size: 12, color: iconColor),
            ),
          ),
        ],
      ),
    );
  }

  String _buildSubtitle(CallLogEntry entry) {
    final typeLabel =
        entry.callType == CallType.video ? 'Video' : 'Audio';
    switch (entry.status) {
      case CallStatus.completed:
        return entry.direction == CallDirection.outgoing
            ? '$typeLabel uscente'
            : '$typeLabel in entrata';
      case CallStatus.missed:
        return 'Chiamata persa';
      case CallStatus.rejected:
        return entry.direction == CallDirection.outgoing
            ? '$typeLabel rifiutata'
            : '$typeLabel rifiutata';
    }
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(dt.year, dt.month, dt.day);
    if (date == today) {
      return DateFormat('HH:mm').format(dt);
    }
    if (date == today.subtract(const Duration(days: 1))) {
      return 'Ieri ${DateFormat('HH:mm').format(dt)}';
    }
    return DateFormat('d MMM', 'it').format(dt);
  }
}

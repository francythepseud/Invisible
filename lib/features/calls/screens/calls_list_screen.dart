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
        return _entries
            .where((e) => e.direction == CallDirection.incoming)
            .toList();
      case _CallFilter.outgoing:
        return _entries
            .where((e) => e.direction == CallDirection.outgoing)
            .toList();
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
        backgroundColor: AppConstants.surfaceBlack,
        elevation: 0,
        title: const Text(
          'Chiamate',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 22),
        ),
        actions: [
          if (_entries.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded),
              tooltip: 'Cancella tutto',
              onPressed: _clearAll,
            ),
        ],
      ),
      body: Theme(
        data: Theme.of(context).copyWith(
          canvasColor: AppConstants.backgroundBlack,
        ),
        child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildFilterBar(),
                Expanded(
                  child: _filtered.isEmpty
                      ? _buildEmptyState()
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            const ColoredBox(color: AppConstants.backgroundBlack),
                            RefreshIndicator(
                              onRefresh: _load,
                              color: AppConstants.primaryBlue,
                              backgroundColor: AppConstants.surfaceBlack,
                              child: ListView.builder(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                itemCount: _filtered.length,
                                itemBuilder: (_, i) => _buildItem(_filtered[i]),
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

  Widget _buildFilterBar() {
    return Container(
      color: AppConstants.surfaceBlack,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          gradient: active
              ? const LinearGradient(
                  colors: [Color(0xFF42A5F5), Color(0xFF1565C0)],
                )
              : null,
          color: active ? null : AppConstants.cardBlack,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active
                ? Colors.transparent
                : AppConstants.divider.withValues(alpha: 0.4),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color:
                active ? Colors.white : AppConstants.textSecondary,
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
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppConstants.textTertiary.withValues(alpha: 0.15),
                  AppConstants.textTertiary.withValues(alpha: 0.05),
                ],
              ),
            ),
            child: Icon(
              Icons.phone_missed_rounded,
              size: 44,
              color: AppConstants.textTertiary.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Nessuna chiamata',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppConstants.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'La cronologia apparirà qui',
            style: TextStyle(fontSize: 14, color: AppConstants.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(CallLogEntry entry) {
    final isMissed = entry.status == CallStatus.missed;
    final isRejected = entry.status == CallStatus.rejected;

    return Dismissible(
      key: Key(entry.id),
      direction: DismissDirection.endToStart,
      background: const SizedBox.shrink(),
      // secondaryBackground per swipe da destra (endToStart) — mostra il delete
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppConstants.error.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline_rounded,
            color: AppConstants.error, size: 26),
      ),
      onDismissed: (_) => _deleteEntry(entry),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        decoration: BoxDecoration(
          color: AppConstants.cardBlack,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: (isMissed || isRejected)
                ? AppConstants.error.withValues(alpha: 0.2)
                : AppConstants.divider.withValues(alpha: 0.15),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              _buildLeadingIcon(entry),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.contactName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: (isMissed || isRejected)
                            ? AppConstants.error
                            : AppConstants.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          _subtitleIcon(entry),
                          size: 13,
                          color: (isMissed || isRejected)
                              ? AppConstants.error.withValues(alpha: 0.7)
                              : AppConstants.textTertiary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _buildSubtitle(entry),
                          style: TextStyle(
                            fontSize: 13,
                            color: (isMissed || isRejected)
                                ? AppConstants.error.withValues(alpha: 0.8)
                                : AppConstants.textTertiary,
                          ),
                        ),
                        if (entry.status == CallStatus.completed &&
                            entry.durationSeconds > 0) ...[
                          const Text(
                            ' · ',
                            style: TextStyle(
                                fontSize: 13, color: AppConstants.textTertiary),
                          ),
                          Text(
                            _formatDuration(entry.durationSeconds),
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppConstants.textTertiary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatDate(entry.startedAt),
                style: TextStyle(
                  fontSize: 12,
                  color: (isMissed || isRejected)
                      ? AppConstants.error.withValues(alpha: 0.7)
                      : AppConstants.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeadingIcon(CallLogEntry entry) {
    final isVideo = entry.callType == CallType.video;
    final isOut = entry.direction == CallDirection.outgoing;
    final isMissed = entry.status == CallStatus.missed;
    final isRejected = entry.status == CallStatus.rejected;

    final List<Color> gradColors;
    if (isMissed || isRejected) {
      gradColors = [
        AppConstants.error.withValues(alpha: 0.8),
        AppConstants.error.withValues(alpha: 0.5),
      ];
    } else if (isOut) {
      gradColors = [const Color(0xFF42A5F5), const Color(0xFF1565C0)];
    } else {
      gradColors = [const Color(0xFF66BB6A), const Color(0xFF2E7D32)];
    }

    final arrowIcon = isOut
        ? Icons.call_made_rounded
        : (isMissed ? Icons.call_missed_rounded : Icons.call_received_rounded);

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradColors,
        ),
      ),
      child: Stack(
        children: [
          Center(
            child: Icon(
              isVideo ? Icons.videocam_rounded : Icons.call_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          Positioned(
            right: 1,
            bottom: 1,
            child: Container(
              width: 17,
              height: 17,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppConstants.backgroundBlack,
                border: Border.all(
                  color: AppConstants.backgroundBlack,
                  width: 1,
                ),
              ),
              child: Icon(
                arrowIcon,
                size: 11,
                color: isMissed || isRejected
                    ? AppConstants.error
                    : (isOut ? const Color(0xFF42A5F5) : AppConstants.success),
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _subtitleIcon(CallLogEntry entry) {
    if (entry.callType == CallType.video) return Icons.videocam_rounded;
    return Icons.call_rounded;
  }

  String _buildSubtitle(CallLogEntry entry) {
    final typeLabel = entry.callType == CallType.video ? 'Video' : 'Audio';
    switch (entry.status) {
      case CallStatus.completed:
        return entry.direction == CallDirection.outgoing
            ? '$typeLabel uscente'
            : '$typeLabel in entrata';
      case CallStatus.missed:
        return 'Chiamata persa';
      case CallStatus.rejected:
        return '$typeLabel rifiutata';
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
    if (date == today) return DateFormat('HH:mm').format(dt);
    if (date == today.subtract(const Duration(days: 1))) {
      return 'Ieri ${DateFormat('HH:mm').format(dt)}';
    }
    return DateFormat('d MMM', 'it').format(dt);
  }
}

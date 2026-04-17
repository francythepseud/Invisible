/// Voce del registro chiamate salvata nel DB cifrato.
class CallLogEntry {
  final String id;
  final String? contactId;
  final String contactName;
  final CallType callType;
  final CallDirection direction;
  final CallStatus status;
  final int durationSeconds;
  final DateTime startedAt;

  const CallLogEntry({
    required this.id,
    this.contactId,
    required this.contactName,
    required this.callType,
    required this.direction,
    required this.status,
    required this.durationSeconds,
    required this.startedAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'contact_id': contactId,
        'contact_name': contactName,
        'call_type': callType.name,
        'direction': direction.name,
        'status': status.name,
        'duration_seconds': durationSeconds,
        'started_at': startedAt.toIso8601String(),
      };

  factory CallLogEntry.fromMap(Map<String, dynamic> m) => CallLogEntry(
        id: m['id'] as String,
        contactId: m['contact_id'] as String?,
        contactName: m['contact_name'] as String,
        callType: CallType.values.firstWhere(
          (e) => e.name == m['call_type'],
          orElse: () => CallType.audio,
        ),
        direction: CallDirection.values.firstWhere(
          (e) => e.name == m['direction'],
          orElse: () => CallDirection.outgoing,
        ),
        status: CallStatus.values.firstWhere(
          (e) => e.name == m['status'],
          orElse: () => CallStatus.completed,
        ),
        durationSeconds: (m['duration_seconds'] as int?) ?? 0,
        startedAt: DateTime.parse(m['started_at'] as String),
      );
}

enum CallType { audio, video }

enum CallDirection { outgoing, incoming }

enum CallStatus { completed, missed, rejected }

import 'package:invisible/core/services/profile_service.dart';
import 'package:invisible/models/call_log_entry.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Gestisce il registro chiamate nel database cifrato.
class CallLogService {
  static final CallLogService _instance = CallLogService._internal();
  factory CallLogService() => _instance;
  CallLogService._internal();

  Database get _db {
    final db = ProfileService().currentDatabase;
    if (db == null) throw Exception('No active profile session');
    return db;
  }

  /// Salva una nuova voce. Chiamare fire-and-forget (nessun await necessario).
  Future<void> saveEntry(CallLogEntry entry) async {
    try {
      await _db.insert(
        'call_log',
        entry.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }

  /// Restituisce le ultime [limit] chiamate ordinate dalla più recente.
  Future<List<CallLogEntry>> getEntries({int limit = 200}) async {
    try {
      final rows = await _db.query(
        'call_log',
        orderBy: 'started_at DESC',
        limit: limit,
      );
      return rows.map(CallLogEntry.fromMap).toList();
    } catch (_) {
      return [];
    }
  }

  /// Elimina una singola voce.
  Future<void> deleteEntry(String id) async {
    try {
      await _db.delete('call_log', where: 'id = ?', whereArgs: [id]);
    } catch (_) {}
  }

  /// Svuota tutto il registro.
  Future<void> clearAll() async {
    try {
      await _db.delete('call_log');
    } catch (_) {}
  }
}

import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

class DatabaseService {
  Database? _database;
  String? _currentProfileId;

  /// Ottiene il database per il profilo specificato
  /// Se il database non esiste, lo crea
  Future<Database> getDatabase(String profileId, String dbKey) async {
    // Se è già aperto il database corretto, ritorna quello
    if (_database != null && _currentProfileId == profileId) {
      return _database!;
    }

    // Chiudi il database precedente se esiste
    await closeDatabase();

    // Ottieni il path del database
    final dbPath = await _getDatabasePath(profileId);

    // Apri/Crea il database criptato
    try {
      _database = await openDatabase(
        dbPath,
        password: dbKey,
        version: 3,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
    } catch (e) {
      // SQLITE_NOTADB (code 26): file corrotto o troncato.
      // Cancelliamo SOLO se il file è 0 byte (creazione interrotta da crash):
      // un file più grande potrebbe avere dati reali o essere password sbagliata.
      if (e.toString().contains('26') || e.toString().contains('not a database')) {
        final file = File(dbPath);
        final size = await file.exists() ? await file.length() : -1;
        if (size == 0) {
          await file.delete();
          _database = await openDatabase(
            dbPath,
            password: dbKey,
            version: 3,
            onCreate: _onCreate,
            onUpgrade: _onUpgrade,
          );
        } else {
          rethrow;
        }
      } else {
        rethrow;
      }
    }

    _currentProfileId = profileId;
    return _database!;
  }

  /// Crea le tabelle del database
  Future<void> _onCreate(Database db, int version) async {
    // Tabella profilo locale
    await db.execute('''
      CREATE TABLE profile (
        id TEXT PRIMARY KEY,
        username TEXT NOT NULL,
        public_key TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        last_login_at INTEGER
      )
    ''');

    // Tabella chiavi crittografiche
    await db.execute('''
      CREATE TABLE crypto_keys (
        id TEXT PRIMARY KEY,
        master_key_private TEXT NOT NULL,
        master_key_public TEXT NOT NULL,
        identity_key_private TEXT NOT NULL,
        identity_key_public TEXT NOT NULL,
        signed_pre_key_private TEXT NOT NULL,
        signed_pre_key_public TEXT NOT NULL,
        signed_pre_key_signature TEXT NOT NULL DEFAULT '',
        signed_pre_key_created_at INTEGER NOT NULL
      )
    ''');

    // Tabella contatti
    await db.execute('''
      CREATE TABLE contacts (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        public_key TEXT NOT NULL,
        identity_key TEXT,
        signed_pre_key TEXT,
        signed_pre_key_sig TEXT,
        avatar_path TEXT,
        blocked INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    // Tabella conversazioni
    await db.execute('''
      CREATE TABLE conversations (
        id TEXT PRIMARY KEY,
        contact_id TEXT NOT NULL,
        contact_name TEXT NOT NULL,
        contact_public_key TEXT NOT NULL,
        last_message_text TEXT,
        last_message_time TEXT,
        unread_count INTEGER DEFAULT 0,
        ratchet_state_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (contact_id) REFERENCES contacts(id)
      )
    ''');

    // Tabella messaggi
    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        sender_id TEXT NOT NULL,
        ciphertext TEXT NOT NULL,
        message_header TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        status TEXT DEFAULT 'sending',
        type TEXT DEFAULT 'text',
        local_path TEXT,
        is_outgoing INTEGER DEFAULT 0,
        decrypted_text TEXT,
        FOREIGN KEY (conversation_id) REFERENCES conversations(id)
      )
    ''');

    // Tabella stato Double Ratchet
    await db.execute('''
      CREATE TABLE ratchet_states (
        id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        root_key TEXT NOT NULL,
        sending_chain_key TEXT,
        receiving_chain_key TEXT,
        our_ratchet_private_key TEXT NOT NULL,
        our_ratchet_public_key TEXT NOT NULL,
        their_ratchet_public_key TEXT,
        send_count INTEGER DEFAULT 0,
        receive_count INTEGER DEFAULT 0,
        previous_send_count INTEGER DEFAULT 0,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (conversation_id) REFERENCES conversations(id)
      )
    ''');

    // Tabella pre-keys locali
    await db.execute('''
      CREATE TABLE prekeys (
        id INTEGER PRIMARY KEY,
        public_key TEXT NOT NULL,
        private_key TEXT NOT NULL,
        used INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');

    // Tabella media
    await db.execute('''
      CREATE TABLE media (
        id TEXT PRIMARY KEY,
        message_id TEXT NOT NULL,
        type TEXT NOT NULL,
        file_path TEXT NOT NULL,
        thumbnail_path TEXT,
        size INTEGER,
        duration INTEGER,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (message_id) REFERENCES messages(id)
      )
    ''');

    // Tabella registro chiamate
    await db.execute(_sqlCallLog);

    // Indici per performance
    await db.execute('CREATE INDEX idx_messages_conversation ON messages(conversation_id)');
    await db.execute('CREATE INDEX idx_messages_timestamp ON messages(timestamp)');
    await db.execute('CREATE INDEX idx_contacts_name ON contacts(name)');
    await db.execute('CREATE INDEX idx_call_log_started ON call_log(started_at)');
  }

  static const _sqlCallLog = '''
    CREATE TABLE call_log (
      id TEXT PRIMARY KEY,
      contact_id TEXT,
      contact_name TEXT NOT NULL,
      call_type TEXT NOT NULL,
      direction TEXT NOT NULL,
      status TEXT NOT NULL,
      duration_seconds INTEGER DEFAULT 0,
      started_at TEXT NOT NULL
    )
  ''';

  /// Gestisce l'upgrade del database
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(_sqlCallLog);
      await db.execute('CREATE INDEX idx_call_log_started ON call_log(started_at)');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE messages ADD COLUMN decrypted_text TEXT');
    }
  }

  /// Ottiene il path del database per il profilo
  Future<String> _getDatabasePath(String profileId) async {
    final directory = await getApplicationDocumentsDirectory();
    final dbDirectory = Directory(join(directory.path, 'databases'));

    // Crea la directory se non esiste
    if (!await dbDirectory.exists()) {
      await dbDirectory.create(recursive: true);
    }

    return join(dbDirectory.path, 'profile_$profileId.db');
  }

  /// Chiude il database corrente
  Future<void> closeDatabase() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
      _currentProfileId = null;
    }
  }

  /// Elimina il database di un profilo
  Future<void> deleteDatabase(String profileId) async {
    await closeDatabase();
    final dbPath = await _getDatabasePath(profileId);
    final file = File(dbPath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Verifica se esiste un database per il profilo
  Future<bool> databaseExists(String profileId) async {
    final dbPath = await _getDatabasePath(profileId);
    return await File(dbPath).exists();
  }
}

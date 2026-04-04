import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Gestisce la registrazione audio per i messaggi vocali.
/// I file vengono salvati in una directory temporanea e passati
/// a [MessageService] per la cifratura AES-256-GCM nel Double Ratchet.
class AudioRecorderService {
  static final AudioRecorderService _instance =
      AudioRecorderService._internal();
  factory AudioRecorderService() => _instance;
  AudioRecorderService._internal();

  final _recorder = AudioRecorder();
  bool _isRecording = false;

  bool get isRecording => _isRecording;

  /// Controlla se il permesso microfono è già concesso.
  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Avvia la registrazione. Il file viene salvato in una cartella temp.
  Future<void> startRecording() async {
    if (_isRecording) return;
    final dir = await getTemporaryDirectory();
    final path = p.join(
      dir.path,
      'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
    );
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 64000,
        sampleRate: 44100,
      ),
      path: path,
    );
    _isRecording = true;
  }

  /// Ferma la registrazione e restituisce il path del file.
  /// Se [cancel] è true elimina il file e restituisce null.
  Future<String?> stopRecording({bool cancel = false}) async {
    if (!_isRecording) return null;
    final path = await _recorder.stop();
    _isRecording = false;
    if (cancel && path != null) {
      try { await File(path).delete(); } catch (_) {}
      return null;
    }
    return path;
  }

  Future<void> dispose() => _recorder.dispose();
}

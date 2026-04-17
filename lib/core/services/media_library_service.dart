import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Gestisce la galleria media in-app (sandbox — mai accessibile dal rullino).
class MediaLibraryService {
  static final MediaLibraryService _instance = MediaLibraryService._internal();
  factory MediaLibraryService() => _instance;
  MediaLibraryService._internal();

  static const _dirName = 'invisible_media';

  Future<Directory> _mediaDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, _dirName));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Copia un file sorgente nella libreria in-app e restituisce il nuovo path.
  Future<String> saveToLibrary(String sourcePath) async {
    final dir = await _mediaDir();
    final ext = p.extension(sourcePath).toLowerCase().isNotEmpty
        ? p.extension(sourcePath).toLowerCase()
        : '.jpg';
    final destName = '${const Uuid().v4()}$ext';
    final dest = File(p.join(dir.path, destName));
    await File(sourcePath).copy(dest.path);
    return dest.path;
  }

  /// Restituisce tutti i file nella libreria, ordinati per data (più recenti prima).
  Future<List<File>> getLibraryItems() async {
    final dir = await _mediaDir();
    if (!await dir.exists()) return [];
    final files = await dir
        .list()
        .where((e) => e is File)
        .cast<File>()
        .toList();
    files.sort((a, b) {
      final aTime = a.statSync().modified;
      final bTime = b.statSync().modified;
      return bTime.compareTo(aTime);
    });
    return files;
  }

  /// Elimina un file dalla libreria in-app.
  Future<void> deleteFromLibrary(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) await file.delete();
  }

  bool isImageFile(String path) {
    final ext = p.extension(path).toLowerCase();
    return ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.heic'].contains(ext);
  }

  bool isVideoFile(String path) {
    final ext = p.extension(path).toLowerCase();
    return ['.mp4', '.mov', '.avi', '.mkv', '.webm', '.3gp'].contains(ext);
  }
}

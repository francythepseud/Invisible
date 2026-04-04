import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:invisible/core/services/media_library_service.dart';
import 'package:invisible/utils/constants.dart';

class MediaGalleryScreen extends StatefulWidget {
  const MediaGalleryScreen({super.key});

  @override
  State<MediaGalleryScreen> createState() => _MediaGalleryScreenState();
}

class _MediaGalleryScreenState extends State<MediaGalleryScreen> {
  final _service = MediaLibraryService();
  List<File> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await _service.getLibraryItems();
    if (mounted) setState(() { _items = items; _loading = false; });
  }

  Future<void> _capturePhoto() async {
    final xfile = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
    );
    if (xfile == null) return;
    await _service.saveToLibrary(xfile.path);
    await _load();
  }

  Future<void> _captureVideo() async {
    final xfile = await ImagePicker().pickVideo(
      source: ImageSource.camera,
      maxDuration: const Duration(minutes: 5),
    );
    if (xfile == null) return;
    await _service.saveToLibrary(xfile.path);
    await _load();
  }

  Future<void> _importPhoto() async {
    final xfile = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (xfile == null) return;
    await _service.saveToLibrary(xfile.path);
    await _load();
  }

  Future<void> _importVideo() async {
    final xfile = await ImagePicker().pickVideo(
      source: ImageSource.gallery,
    );
    if (xfile == null) return;
    await _service.saveToLibrary(xfile.path);
    await _load();
  }

  void _showImportMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppConstants.surfaceBlack,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Aggiungi media',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppConstants.textPrimary,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _ImportTile(
                    icon: Icons.camera_alt_rounded,
                    label: 'Foto\ncamera',
                    color: AppConstants.primaryBlue,
                    onTap: () { Navigator.pop(context); _capturePhoto(); },
                  ),
                  _ImportTile(
                    icon: Icons.videocam_rounded,
                    label: 'Video\ncamera',
                    color: Colors.deepOrangeAccent,
                    onTap: () { Navigator.pop(context); _captureVideo(); },
                  ),
                  _ImportTile(
                    icon: Icons.photo_library_outlined,
                    label: 'Importa\nfoto',
                    color: Colors.purpleAccent,
                    onTap: () { Navigator.pop(context); _importPhoto(); },
                  ),
                  _ImportTile(
                    icon: Icons.video_library_outlined,
                    label: 'Importa\nvideo',
                    color: Colors.tealAccent,
                    onTap: () { Navigator.pop(context); _importVideo(); },
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _delete(File file) async {
    final isVideo = _service.isVideoFile(file.path);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppConstants.surfaceBlack,
        title: Text('Elimina ${isVideo ? 'video' : 'foto'}'),
        content: Text('Vuoi eliminare ${isVideo ? 'questo video' : 'questa foto'} dalla libreria in-app?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppConstants.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Elimina', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _service.deleteFromLibrary(file.path);
      await _load();
    }
  }

  void _viewFullscreen(File file) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _service.isVideoFile(file.path)
            ? _VideoViewer(file: file)
            : _ImageViewer(file: file),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.backgroundBlack,
      appBar: AppBar(
        backgroundColor: AppConstants.surfaceBlack,
        elevation: 0,
        title: const Text('Media', style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Aggiungi media',
            onPressed: _showImportMenu,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? _buildEmpty()
              : _buildGrid(),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.paddingXLarge),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: AppConstants.primaryBlue.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.photo_library_outlined,
                size: 44,
                color: AppConstants.primaryBlue,
              ),
            ),
            const SizedBox(height: AppConstants.paddingLarge),
            const Text(
              'Nessun media',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppConstants.textPrimary,
              ),
            ),
            const SizedBox(height: AppConstants.paddingSmall),
            const Text(
              'Scatta foto/video o importali dal telefono.\nRimangono nella sandbox dell\'app.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppConstants.textTertiary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppConstants.paddingXLarge),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.primaryBlue,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              label: const Text('Aggiungi media', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              onPressed: _showImportMenu,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid() {
    return RefreshIndicator(
      onRefresh: _load,
      color: AppConstants.primaryBlue,
      child: GridView.builder(
        padding: const EdgeInsets.all(4),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 3,
          mainAxisSpacing: 3,
        ),
        itemCount: _items.length,
        itemBuilder: (context, i) {
          final file = _items[i];
          return GestureDetector(
            onTap: () => _viewFullscreen(file),
            onLongPress: () => _delete(file),
            child: _GridTile(file: file, service: _service),
          );
        },
      ),
    );
  }
}

// ─── Grid tile con thumbnail ──────────────────────────────────────────────────

class _GridTile extends StatefulWidget {
  final File file;
  final MediaLibraryService service;
  const _GridTile({required this.file, required this.service});

  @override
  State<_GridTile> createState() => _GridTileState();
}

class _GridTileState extends State<_GridTile> {
  Uint8List? _thumb;
  bool _thumbLoaded = false;

  @override
  void initState() {
    super.initState();
    if (widget.service.isVideoFile(widget.file.path)) {
      _loadVideoThumbnail();
    }
  }

  Future<void> _loadVideoThumbnail() async {
    final thumb = await VideoThumbnail.thumbnailData(
      video: widget.file.path,
      imageFormat: ImageFormat.JPEG,
      maxWidth: 200,
      quality: 70,
    );
    if (mounted) setState(() { _thumb = thumb; _thumbLoaded = true; });
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.service.isVideoFile(widget.file.path);
    final isImage = widget.service.isImageFile(widget.file.path);

    Widget content;
    if (isImage) {
      content = Image.file(widget.file, fit: BoxFit.cover);
    } else if (isVideo) {
      if (_thumbLoaded && _thumb != null) {
        content = Image.memory(_thumb!, fit: BoxFit.cover);
      } else if (_thumbLoaded) {
        content = const Center(child: Icon(Icons.videocam_rounded, color: AppConstants.textTertiary, size: 36));
      } else {
        content = const Center(child: CircularProgressIndicator(strokeWidth: 2));
      }
    } else {
      content = const Center(child: Icon(Icons.insert_drive_file_rounded, color: AppConstants.textTertiary, size: 36));
    }

    return Container(
      color: AppConstants.surfaceBlack,
      child: Stack(
        fit: StackFit.expand,
        children: [
          content,
          if (isVideo)
            Center(
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.55),
                ),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Image viewer ─────────────────────────────────────────────────────────────

class _ImageViewer extends StatelessWidget {
  final File file;
  const _ImageViewer({required this.file});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.shield_rounded, color: AppConstants.primaryBlue),
            tooltip: 'Foto in sandbox — non visibile nella galleria del telefono',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Foto protetta nella sandbox dell\'app'),
                  backgroundColor: AppConstants.primaryBlue,
                ),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          child: Image.file(file, fit: BoxFit.contain),
        ),
      ),
    );
  }
}

// ─── Video viewer ─────────────────────────────────────────────────────────────

class _VideoViewer extends StatefulWidget {
  final File file;
  const _VideoViewer({required this.file});

  @override
  State<_VideoViewer> createState() => _VideoViewerState();
}

class _VideoViewerState extends State<_VideoViewer> {
  late VideoPlayerController _ctrl;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _ctrl = VideoPlayerController.file(widget.file)
      ..initialize().then((_) {
        if (mounted) setState(() => _initialized = true);
      });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.shield_rounded, color: AppConstants.primaryBlue),
            tooltip: 'Video in sandbox — non visibile nella galleria del telefono',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Video protetto nella sandbox dell\'app'),
                  backgroundColor: AppConstants.primaryBlue,
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: _initialized
            ? Column(
                children: [
                  Expanded(
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: _ctrl.value.aspectRatio,
                        child: VideoPlayer(_ctrl),
                      ),
                    ),
                  ),
                  _VideoControls(controller: _ctrl),
                  const SizedBox(height: 8),
                ],
              )
            : const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _VideoControls extends StatefulWidget {
  final VideoPlayerController controller;
  const _VideoControls({required this.controller});

  @override
  State<_VideoControls> createState() => _VideoControlsState();
}

class _VideoControlsState extends State<_VideoControls> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_update);
  }

  void _update() { if (mounted) setState(() {}); }

  @override
  void dispose() {
    widget.controller.removeListener(_update);
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final pos = ctrl.value.position;
    final dur = ctrl.value.duration;
    final isPlaying = ctrl.value.isPlaying;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          VideoProgressIndicator(
            ctrl,
            allowScrubbing: true,
            colors: VideoProgressColors(
              playedColor: AppConstants.primaryBlue,
              bufferedColor: AppConstants.primaryBlue.withValues(alpha: 0.3),
              backgroundColor: AppConstants.surfaceBlack,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_fmt(pos), style: const TextStyle(color: AppConstants.textTertiary, fontSize: 12)),
              IconButton(
                icon: Icon(
                  isPlaying ? Icons.pause_circle_rounded : Icons.play_circle_rounded,
                  color: Colors.white,
                  size: 48,
                ),
                onPressed: () => isPlaying ? ctrl.pause() : ctrl.play(),
              ),
              Text(_fmt(dur), style: const TextStyle(color: AppConstants.textTertiary, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Import tile ──────────────────────────────────────────────────────────────

class _ImportTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ImportTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: AppConstants.textSecondary),
          ),
        ],
      ),
    );
  }
}

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:invisible/core/services/audio_recorder_service.dart';
import 'package:invisible/core/services/call_service.dart';
import 'package:invisible/core/services/profile_service.dart';
import 'package:invisible/core/services/message_service.dart';
import 'package:invisible/core/services/media_library_service.dart';
import 'package:invisible/core/services/session_service.dart';
import 'package:invisible/features/calls/screens/call_screen.dart';
import 'package:invisible/features/chat/widgets/audio_message_bubble.dart';
import 'package:invisible/models/contact.dart';
import 'package:invisible/models/conversation.dart';
import 'package:invisible/features/chat/screens/safety_numbers_screen.dart';
import 'package:invisible/models/message.dart';
import 'package:invisible/utils/constants.dart';

class ChatScreen extends StatefulWidget {
  final Conversation conversation;

  const ChatScreen({super.key, required this.conversation});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _profileService = ProfileService();
  final _messageService = MessageService();
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  List<Message> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  bool _showEmojiPicker = false;
  bool _hasText = false;
  StreamSubscription<Message>? _incomingSubscription;

  // Multi-selezione messaggi
  final Set<String> _selectedIds = {};
  bool get _selectionMode => _selectedIds.isNotEmpty;

  // Pending attachment before sending
  File? _pendingFile;
  String? _pendingFileName;
  MessageType _pendingType = MessageType.text;

  // Registrazione vocale
  final _audioRecorder = AudioRecorderService();
  bool _isRecording = false;
  Duration _recordingDuration = Duration.zero;
  bool _recordingDotVisible = true;
  Timer? _recordingTimer;

  // Read receipts
  StreamSubscription<String>? _readReceiptSubscription;

  // Scroll / lazy-load / reply
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _isUserAtBottom = true;
  int _unseenMessages = 0;
  Message? _replyingTo;
  static const _pageSize = 40;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _messageController.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
    _incomingSubscription = SessionService()
        .messagesFor(widget.conversation.id)
        .listen(_onIncomingMessage);

    // Ascolta le read receipt per aggiornare i tick blu
    _readReceiptSubscription = SessionService()
        .readReceiptStream
        .where((convId) => convId == widget.conversation.id)
        .listen((_) => _onReadReceiptReceived());

  }

  void _onIncomingMessage(Message message) {
    if (!mounted) return;
    setState(() {
      _messages.add(message);
      if (!_isUserAtBottom) _unseenMessages++;
    });
    if (_isUserAtBottom) _scrollToBottom();
    _messageService.sendReadReceipt(widget.conversation.id);
  }

  void _onReadReceiptReceived() {
    if (!mounted) return;
    // Aggiorna lo stato visuale di tutti i messaggi uscenti a "read"
    setState(() {
      _messages = _messages.map((m) {
        if (m.isOutgoing && m.status != MessageStatus.read) {
          return m.copyWith(status: MessageStatus.read);
        }
        return m;
      }).toList();
    });
  }

  void _onTextChanged() {
    final has = _messageController.text.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus && _showEmojiPicker) {
      setState(() => _showEmojiPicker = false);
    }
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _incomingSubscription?.cancel();
    _readReceiptSubscription?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  // ─── Registrazione vocale ─────────────────────────────────────────────────

  Future<void> _startRecording() async {
    // Verifica permesso microfono
    if (!await _audioRecorder.hasPermission()) {
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Permesso microfono non concesso'),
              backgroundColor: AppConstants.error,
            ),
          );
        }
        return;
      }
    }
    await _audioRecorder.startRecording();
    setState(() {
      _isRecording = true;
      _recordingDuration = Duration.zero;
      _recordingDotVisible = true;
    });
    // Timer: ogni 500ms alterna il pallino e ogni 1000ms incrementa la durata
    _recordingTimer = Timer.periodic(const Duration(milliseconds: 500), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        _recordingDotVisible = !_recordingDotVisible;
        if (t.tick.isEven) {
          _recordingDuration += const Duration(seconds: 1);
        }
      });
    });
  }

  Future<void> _stopRecording({bool cancel = false}) async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    final path = await _audioRecorder.stopRecording(cancel: cancel);
    setState(() {
      _isRecording = false;
      _recordingDuration = Duration.zero;
    });
    if (path != null && !cancel) {
      await _sendAudioMessage(path);
    }
  }

  Future<void> _sendAudioMessage(String path) async {
    setState(() => _isSending = true);
    try {
      final profile = _profileService.currentProfile;
      if (profile == null) return;
      final message = await _messageService.sendMessage(
        conversationId: widget.conversation.id,
        plaintext: 'Messaggio vocale',
        senderId: profile.id,
        type: MessageType.audio,
        localPath: path,
      );
      if (mounted) {
        setState(() {
          _messages.add(message);
          _isSending = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore invio vocale: $e'),
            backgroundColor: AppConstants.error,
          ),
        );
      }
    }
  }

  String _formatRecordingDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _loadMessages() async {
    try {
      // Carica TUTTI i messaggi (come l'originale), nessun limit
      final messages = await _messageService.getMessages(widget.conversation.id);
      final hadUnread = messages.any((m) => !m.isOutgoing && m.status != MessageStatus.read);
      await _messageService.markMessagesAsRead(widget.conversation.id);
      if (mounted) {
        setState(() {
          _messages = messages;
          _isLoading = false;
          _hasMore = false; // tutti già caricati
        });
        _scrollToBottom(animated: false);
        if (hadUnread) {
          _messageService.sendReadReceipt(widget.conversation.id);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMoreMessages() async {
    // Tutti i messaggi sono già caricati all'avvio, lazy load non necessario
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      if (animated) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(0);
      }
    });
  }

  void _toggleEmojiPicker() {
    if (_showEmojiPicker) {
      setState(() => _showEmojiPicker = false);
      _focusNode.requestFocus();
    } else {
      _focusNode.unfocus();
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) setState(() => _showEmojiPicker = true);
      });
    }
  }

  Future<void> _pickFromInvisibleGallery() async {
    Navigator.of(context).pop();
    final file = await Navigator.of(context).push<File>(
      MaterialPageRoute(
        builder: (_) => const _InvisibleGalleryPicker(),
        fullscreenDialog: true,
      ),
    );
    if (file == null) return;
    final isVideo = MediaLibraryService().isVideoFile(file.path);
    await _saveAttachmentToSandbox(
      file.path,
      isVideo ? MessageType.video : MessageType.image,
    );
  }

  Future<void> _pickFile() async {
    Navigator.of(context).pop();
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;
    if (picked.path == null) return;
    await _saveAttachmentToSandbox(
      picked.path!,
      MessageType.file,
      name: picked.name,
    );
  }

  Future<void> _takeCameraPhoto() async {
    Navigator.of(context).pop();
    try {
      final picker = ImagePicker();
      final photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1920,
      );
      if (photo == null) return;
      await _saveAttachmentToSandbox(photo.path, MessageType.image);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore fotocamera: $e'),
            backgroundColor: AppConstants.error,
          ),
        );
      }
    }
  }

  Future<void> _shareLocation() async {
    Navigator.of(context).pop();
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Attiva la posizione nelle impostazioni'),
              backgroundColor: AppConstants.error,
            ),
          );
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) {
        await openAppSettings();
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      final lat = position.latitude.toStringAsFixed(6);
      final lon = position.longitude.toStringAsFixed(6);
      final locationText = '📍 $lat,$lon';

      setState(() => _isSending = true);
      try {
        final profile = _profileService.currentProfile;
        if (profile == null) return;
        final message = await _messageService.sendMessage(
          conversationId: widget.conversation.id,
          plaintext: locationText,
          senderId: profile.id,
          type: MessageType.text,
        );
        if (mounted) {
          setState(() {
            _messages.add(message);
            _isSending = false;
          });
          _scrollToBottom();
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isSending = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Errore invio posizione: $e'),
              backgroundColor: AppConstants.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Impossibile ottenere posizione: $e'),
            backgroundColor: AppConstants.error,
          ),
        );
      }
    }
  }

  Future<void> _saveAttachmentToSandbox(
    String srcPath,
    MessageType type, {
    String? name,
  }) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final subDir = type == MessageType.image ? 'media' : 'files';
      final dest = Directory(p.join(dir.path, subDir));
      if (!await dest.exists()) await dest.create(recursive: true);
      final filename = name ?? p.basename(srcPath);
      final saved = await File(srcPath).copy(p.join(dest.path, filename));
      if (mounted) {
        setState(() {
          _pendingFile = saved;
          _pendingFileName = filename;
          _pendingType = type;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore allegato: $e'),
            backgroundColor: AppConstants.error,
          ),
        );
      }
    }
  }

  void _showAttachMenu() {
    if (_showEmojiPicker) setState(() => _showEmojiPicker = false);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppConstants.surfaceBlack,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.paddingXLarge,
            vertical: AppConstants.paddingLarge,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildAttachOption(
                icon: Icons.camera_alt_rounded,
                label: 'Fotocamera',
                color: const Color(0xFFFF7043),
                onTap: _takeCameraPhoto,
              ),
              _buildAttachOption(
                icon: Icons.photo_library_rounded,
                label: 'Galleria',
                color: Colors.purpleAccent,
                onTap: _pickFromInvisibleGallery,
              ),
              _buildAttachOption(
                icon: Icons.insert_drive_file_rounded,
                label: 'File',
                color: AppConstants.primaryBlue,
                onTap: _pickFile,
              ),
              _buildAttachOption(
                icon: Icons.location_on_rounded,
                label: 'Posizione',
                color: const Color(0xFF26A69A),
                onTap: _shareLocation,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAttachOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Icon(icon, color: color, size: 30),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppConstants.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if ((text.isEmpty && _pendingFile == null) || _isSending) return;

    setState(() => _isSending = true);

    try {
      final profile = _profileService.currentProfile;
      if (profile == null) throw Exception('No active profile');

      final String content;
      if (_pendingFile != null) {
        content = text.isNotEmpty ? text : (_pendingFileName ?? 'file');
      } else {
        content = text;
      }

      final message = await _messageService.sendMessage(
        conversationId: widget.conversation.id,
        plaintext: content,
        senderId: profile.id,
        type: _pendingType,
        localPath: _pendingFile?.path,
      );

      _messageController.clear();

      if (mounted) {
        setState(() {
          _messages.add(message);
          _isSending = false;
          _pendingFile = null;
          _pendingFileName = null;
          _pendingType = MessageType.text;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore invio: $e'),
            backgroundColor: AppConstants.error,
          ),
        );
      }
    }
  }

  void _toggleSelect(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _clearSelection() => setState(() => _selectedIds.clear());

  Future<void> _deleteSelectedMessages() async {
    final count = _selectedIds.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppConstants.surfaceBlack,
        title: Text('Elimina $count ${count == 1 ? 'messaggio' : 'messaggi'}'),
        content: Text(
          'Vuoi eliminare ${count == 1 ? 'questo messaggio' : 'i $count messaggi selezionati'}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppConstants.error),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final ids = Set<String>.from(_selectedIds);
    for (final id in ids) {
      await _messageService.deleteMessage(id);
    }
    if (mounted) {
      setState(() {
        _messages.removeWhere((m) => ids.contains(m.id));
        _selectedIds.clear();
      });
    }
  }

  Future<void> _deleteMessage(Message message) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppConstants.surfaceBlack,
        title: const Text('Elimina messaggio'),
        content: const Text('Vuoi eliminare questo messaggio?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppConstants.error),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _messageService.deleteMessage(message.id);
      if (mounted) {
        setState(() => _messages.removeWhere((m) => m.id == message.id));
      }
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.backgroundBlack,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildEncryptionBanner(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? _buildEmptyState()
                    : _buildMessageList(),
          ),
          if (_pendingFile != null) _buildAttachmentPreview(),
          if (_replyingTo != null) _buildReplyPreview(),
          _buildInputBar(),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: _showEmojiPicker
                ? SizedBox(
                    height: 256,
                    child: EmojiPicker(
                      textEditingController: _messageController,
                      config: Config(
                        height: 256,
                        emojiViewConfig: EmojiViewConfig(
                          emojiSizeMax: 28,
                          backgroundColor: AppConstants.surfaceBlack,
                        ),
                        searchViewConfig: const SearchViewConfig(
                          backgroundColor: AppConstants.cardBlack,
                          buttonIconColor: AppConstants.primaryBlue,
                        ),
                        categoryViewConfig: const CategoryViewConfig(
                          backgroundColor: AppConstants.surfaceBlack,
                          iconColor: AppConstants.textSecondary,
                          iconColorSelected: AppConstants.primaryBlue,
                          indicatorColor: AppConstants.primaryBlue,
                        ),
                        bottomActionBarConfig: const BottomActionBarConfig(
                          backgroundColor: AppConstants.surfaceBlack,
                          buttonColor: AppConstants.primaryBlue,
                          buttonIconColor: Colors.white,
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    if (_selectionMode) {
      return AppBar(
        backgroundColor: AppConstants.surfaceBlack,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: _clearSelection,
        ),
        title: Text(
          '${_selectedIds.length} selezionat${_selectedIds.length == 1 ? 'o' : 'i'}',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: AppConstants.error),
            tooltip: 'Elimina selezionati',
            onPressed: _deleteSelectedMessages,
          ),
        ],
      );
    }

    final name = widget.conversation.contactName;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return AppBar(
      backgroundColor: AppConstants.surfaceBlack,
      elevation: 0,
      titleSpacing: 0,
      title: Row(
        children: [
          _buildGradientAvatar(initial, radius: 20),
          const SizedBox(width: AppConstants.paddingSmall),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Crittografato end-to-end',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppConstants.success.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.call_rounded),
          tooltip: 'Chiamata audio',
          onPressed: _startAudioCall,
        ),
        IconButton(
          icon: const Icon(Icons.videocam_rounded),
          tooltip: 'Videochiamata',
          onPressed: _startVideoCall,
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (value) async {
            if (value == 'safety_numbers') {
              final contact = await _getContact();
              if (contact == null || !mounted) return;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SafetyNumbersScreen(contact: contact),
                ),
              );
            }
          },
          itemBuilder: (ctx) => [
            const PopupMenuItem(
              value: 'safety_numbers',
              child: Row(
                children: [
                  Icon(Icons.verified_user_outlined, size: 20),
                  SizedBox(width: 12),
                  Text('Verifica identità'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _startAudioCall() async {
    final contact = await _getContact();
    if (contact == null || !mounted) return;
    final ok = await CallService().initiateCall(contact, isVideo: false);
    if (!ok || !mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CallScreen(
          contactName: widget.conversation.contactName,
          isVideo: false,
          isOutgoing: true,
        ),
      ),
    );
  }

  Future<void> _startVideoCall() async {
    final contact = await _getContact();
    if (contact == null || !mounted) return;
    final ok = await CallService().initiateCall(contact, isVideo: true);
    if (!ok || !mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CallScreen(
          contactName: widget.conversation.contactName,
          isVideo: true,
          isOutgoing: true,
        ),
      ),
    );
  }

  Future<Contact?> _getContact() async {
    try {
      final db = _profileService.currentDatabase;
      if (db == null) return null;
      final rows = await db.query(
        'contacts',
        where: 'id = ?',
        whereArgs: [widget.conversation.contactId],
      );
      if (rows.isEmpty) return null;
      return Contact.fromJson(rows.first);
    } catch (_) {
      return null;
    }
  }

  Widget _buildGradientAvatar(String initial, {double radius = 20}) {
    final colors = _avatarColors(initial);
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            color: Colors.white,
            fontSize: radius * 0.85,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  List<Color> _avatarColors(String initial) {
    final idx = initial.codeUnitAt(0) % _gradients.length;
    return _gradients[idx];
  }

  static const _gradients = [
    [Color(0xFF2196F3), Color(0xFF0D47A1)],
    [Color(0xFF9C27B0), Color(0xFF4A148C)],
    [Color(0xFF00BCD4), Color(0xFF006064)],
    [Color(0xFF4CAF50), Color(0xFF1B5E20)],
    [Color(0xFFFF5722), Color(0xFFBF360C)],
    [Color(0xFFE91E63), Color(0xFF880E4F)],
    [Color(0xFF607D8B), Color(0xFF263238)],
  ];

  Widget _buildEncryptionBanner() => const SizedBox.shrink();

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.paddingLarge),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 72,
              color: AppConstants.textTertiary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: AppConstants.paddingMedium),
            Text(
              'Nessun messaggio',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppConstants.textSecondary,
                  ),
            ),
            const SizedBox(height: AppConstants.paddingSmall),
            Text(
              'Scrivi il primo messaggio a ${widget.conversation.contactName}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppConstants.textTertiary,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageList() {
    final messages = _messages.reversed.toList();
    return GestureDetector(
      onTap: () {
        _focusNode.unfocus();
        if (_showEmojiPicker) setState(() => _showEmojiPicker = false);
      },
      child: Stack(
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: (scrollInfo) {
              final px = scrollInfo.metrics.pixels;
              final atBottom = px <= 80;
              if (atBottom != _isUserAtBottom) {
                setState(() {
                  _isUserAtBottom = atBottom;
                  if (atBottom) _unseenMessages = 0;
                });
              }
              // lazy load: quando si arriva in cima (maxScrollExtent con reverse)
              if (!_isLoadingMore &&
                  _hasMore &&
                  px >= scrollInfo.metrics.maxScrollExtent - 200) {
                _loadMoreMessages();
              }
              return false;
            },
            child: ListView.builder(
              controller: _scrollController,
              reverse: true,
              physics: const BouncingScrollPhysics(),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: messages.length + (_isLoadingMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (_isLoadingMore && index == messages.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  );
                }
                final msg = messages[index];
                final prev = index < messages.length - 1 ? messages[index + 1] : null;
                final showDate = prev == null || !_isSameDay(prev.timestamp, msg.timestamp);
                return Column(
                  key: ValueKey(msg.id),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showDate) _buildDateSeparator(msg.timestamp),
                    _buildSwipeWrapper(msg),
                  ],
                );
              },
            ),
          ),
          // Badge nuovi messaggi
          if (_unseenMessages > 0 && !_isUserAtBottom)
            Positioned(
              bottom: 20,
              right: 16,
              child: GestureDetector(
                onTap: () {
                  _scrollToBottom();
                  setState(() => _unseenMessages = 0);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF42A5F5),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    '$_unseenMessages ${_unseenMessages == 1 ? 'nuovo messaggio' : 'nuovi messaggi'}',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSwipeWrapper(Message message) {
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity != null && details.primaryVelocity! > 250) {
          setState(() => _replyingTo = message);
        }
      },
      child: _buildMessageBubble(message),
    );
  }

  Widget _buildDateSeparator(DateTime date) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF7C3AED).withValues(alpha: 0.15),
                const Color(0xFF4F2085).withValues(alpha: 0.15),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFF7C3AED).withValues(alpha: 0.25),
              width: 1,
            ),
          ),
          child: Text(
            _formatDateLabel(date),
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFFB39DDB),
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(Message message) {
    final isOut = message.isOutgoing;
    final text = message.decryptedText ?? '[Messaggio criptato]';
    final isSelected = _selectedIds.contains(message.id);
    final maxBubbleWidth = MediaQuery.of(context).size.width * 0.78;

    final bubbleRadius = BorderRadius.only(
      topLeft: const Radius.circular(20),
      topRight: const Radius.circular(20),
      bottomLeft: Radius.circular(isOut ? 20 : 5),
      bottomRight: Radius.circular(isOut ? 5 : 20),
    );

    final bubble = Container(
      constraints: BoxConstraints(maxWidth: maxBubbleWidth),
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        gradient: isOut
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF7C3AED), Color(0xFF4F2085)],
              )
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0D3D4A), Color(0xFF082530)],
              ),
        borderRadius: bubbleRadius,
        border: isOut
            ? Border.all(color: const Color(0xFF9F5FFF).withValues(alpha: 0.3), width: 1)
            : Border.all(color: const Color(0xFF1A6B7A).withValues(alpha: 0.5), width: 1),
        boxShadow: [
          BoxShadow(
            color: isOut
                ? const Color(0xFF7C3AED).withValues(alpha: 0.3)
                : const Color(0xFF0D3D4A).withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: bubbleRadius,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildMessageContent(message, text, isOut),
            Padding(
              padding: const EdgeInsets.only(right: 10, bottom: 5, left: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatTime(message.timestamp),
                    style: TextStyle(
                      fontSize: 10,
                      color: isOut
                          ? Colors.white.withValues(alpha: 0.5)
                          : AppConstants.textTertiary,
                    ),
                  ),
                  if (isOut) ...[
                    const SizedBox(width: 4),
                    _buildStatusIcon(message.status),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );

    final checkmark = AnimatedSwitcher(
      duration: const Duration(milliseconds: 150),
      child: isSelected
          ? const Icon(Icons.check_circle_rounded,
              color: AppConstants.primaryBlue, size: 20, key: ValueKey(true))
          : const Icon(Icons.radio_button_unchecked_rounded,
              color: AppConstants.textTertiary, size: 20, key: ValueKey(false)),
    );

    return GestureDetector(
      onTap: _selectionMode ? () => _toggleSelect(message.id) : null,
      onLongPress: () => _selectionMode
          ? _toggleSelect(message.id)
          : _showMessageActions(message, text),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        color: isSelected
            ? AppConstants.primaryBlue.withValues(alpha: 0.18)
            : Colors.transparent,
        padding: EdgeInsets.only(
          left: isOut ? 48 : 8,
          right: isOut ? 8 : 48,
          top: 2,
          bottom: 2,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment:
              isOut ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (_selectionMode && !isOut) ...[
              checkmark,
              const SizedBox(width: 6),
            ],
            bubble,
            if (_selectionMode && isOut) ...[
              const SizedBox(width: 6),
              checkmark,
            ],
          ],
        ),
      ),
    );
  }
  Widget _buildMessageContent(Message message, String text, bool isOut) {
    if (message.type == MessageType.audio && message.localPath != null) {
      return AudioMessageBubble(
        localPath: message.localPath!,
        isOutgoing: isOut,
      );
    }

    if (message.type == MessageType.image && message.localPath != null) {
      final file = File(message.localPath!);
      return ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 220,
          maxHeight: 220,
          minWidth: 120,
          minHeight: 80,
        ),
        child: file.existsSync()
            ? Image.file(file, fit: BoxFit.cover)
            : Container(
                width: 200,
                height: 120,
                color: AppConstants.surfaceBlack,
                child: const Icon(
                  Icons.broken_image_rounded,
                  color: AppConstants.textTertiary,
                ),
              ),
      );
    }

    if (message.type == MessageType.file) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.insert_drive_file_rounded,
                color: isOut ? Colors.white : const Color(0xFF7DD8E4),
                size: 22,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                style: TextStyle(
                  color: isOut ? Colors.white : const Color(0xFFCCF0F5),
                  fontSize: 14,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
          ],
        ),
      );
    }

    // Location message (starts with 📍 lat,lon)
    if (text.startsWith('📍 ')) {
      return _buildLocationBubble(text, isOut);
    }

    // Text message
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Text(
        text,
        style: TextStyle(
          color: isOut ? Colors.white : const Color(0xFFCCF0F5),
          fontSize: 15,
          height: 1.45,
          letterSpacing: 0.1,
        ),
      ),
    );
  }

  Widget _buildLocationBubble(String text, bool isOut) {
    // Parse "📍 lat,lon"
    final coords = text.replaceFirst('📍 ', '').trim();
    final parts = coords.split(',');

    return GestureDetector(
      onTap: () async {
        try {
          Uri uri;
          if (Platform.isIOS) {
            uri = Uri.parse('maps://?q=$coords');
          } else {
            uri = Uri.parse('geo:$coords?q=$coords');
          }
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri);
          } else {
            // Fallback: prova con geo: generico
            final fallback = Uri.parse('geo:0,0?q=$coords');
            await launchUrl(fallback, mode: LaunchMode.externalApplication);
          }
        } catch (_) {}
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF26A69A).withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.location_on_rounded,
                color: Color(0xFF4DB6AC),
                size: 24,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Posizione',
                    style: TextStyle(
                      color: isOut ? Colors.white : const Color(0xFFCCF0F5),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    parts.length == 2
                        ? '${double.tryParse(parts[0])?.toStringAsFixed(4) ?? parts[0]}, '
                          '${double.tryParse(parts[1])?.toStringAsFixed(4) ?? parts[1]}'
                        : coords,
                    style: TextStyle(
                      color: isOut
                          ? Colors.white70
                          : const Color(0xFF99D8E0),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Tocca per aprire in Maps',
                    style: TextStyle(
                      color: const Color(0xFF4DB6AC).withValues(alpha: 0.9),
                      fontSize: 11,
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

  Widget _buildStatusIcon(MessageStatus status) {
    switch (status) {
      case MessageStatus.sending:
        return const Icon(Icons.access_time_rounded,
            size: 13, color: Colors.white54);
      case MessageStatus.sent:
        return const Icon(Icons.check_rounded,
            size: 13, color: Colors.white60);
      case MessageStatus.delivered:
        return const Icon(Icons.done_all_rounded,
            size: 13, color: Colors.white60);
      case MessageStatus.read:
        return const Icon(Icons.done_all_rounded,
            size: 13, color: Color(0xFF64B5F6));
      case MessageStatus.failed:
        return const Icon(Icons.error_outline_rounded,
            size: 13, color: AppConstants.error);
    }
  }

  void _showMessageActions(Message message, String text) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppConstants.surfaceBlack,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppConstants.textTertiary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline_rounded,
                  color: AppConstants.textSecondary),
              title: const Text('Seleziona'),
              onTap: () {
                Navigator.pop(context);
                _toggleSelect(message.id);
              },
            ),
            if (message.type == MessageType.text) ...[
              ListTile(
                leading: const Icon(Icons.copy_rounded,
                    color: AppConstants.textSecondary),
                title: const Text('Copia testo'),
                onTap: () {
                  Navigator.pop(context);
                  Clipboard.setData(ClipboardData(text: text));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Testo copiato'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
            ],
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: AppConstants.error),
              title: const Text('Elimina',
                  style: TextStyle(color: AppConstants.error)),
              onTap: () {
                Navigator.pop(context);
                _deleteMessage(message);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentPreview() {
    final isImage = _pendingType == MessageType.image;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppConstants.cardBlack,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppConstants.primaryBlue.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          if (isImage && _pendingFile != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                _pendingFile!,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
              ),
            )
          else
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppConstants.primaryBlue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.insert_drive_file_rounded,
                color: AppConstants.primaryBlue,
              ),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _pendingFileName ?? 'allegato',
              style: const TextStyle(
                color: AppConstants.textPrimary,
                fontSize: 13,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded,
                color: AppConstants.textTertiary, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => setState(() {
              _pendingFile = null;
              _pendingFileName = null;
              _pendingType = MessageType.text;
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildReplyPreview() {
    final reply = _replyingTo!;
    final text = reply.decryptedText ?? '';
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppConstants.cardBlack,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFF7C3AED).withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF7C3AED),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reply.isOutgoing ? 'Tu' : widget.conversation.contactName,
                  style: const TextStyle(
                    color: Color(0xFFB39DDB),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  text.isNotEmpty ? text : '📎 Allegato',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppConstants.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18, color: AppConstants.textTertiary),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => setState(() => _replyingTo = null),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: BoxDecoration(
        color: AppConstants.surfaceBlack,
        border: Border(
          top: BorderSide(color: AppConstants.divider.withValues(alpha: 0.5)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: _isRecording ? _buildRecordingBar() : _buildNormalInputRow(),
      ),
    );
  }

  /// Barra durante la registrazione: pallino animato + timer + annulla + invia
  Widget _buildRecordingBar() {
    return Row(
      children: [
        AnimatedOpacity(
          opacity: _recordingDotVisible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: Container(
            width: 12,
            height: 12,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.red,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          _formatRecordingDuration(_recordingDuration),
          style: const TextStyle(
            color: Colors.red,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
        const Spacer(),
        const Text(
          'Rilascia per inviare',
          style: TextStyle(fontSize: 12, color: AppConstants.textTertiary),
        ),
        const Spacer(),
        // Annulla
        GestureDetector(
          onTap: () => _stopRecording(cancel: true),
          child: Container(
            padding: const EdgeInsets.all(8),
            child: const Icon(
              Icons.delete_outline_rounded,
              color: AppConstants.error,
              size: 24,
            ),
          ),
        ),
        const SizedBox(width: 4),
        // Invia manuale (alternativa al rilascio del long press)
        GestureDetector(
          onTap: () => _stopRecording(),
          child: Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.red,
            ),
            child: const Icon(
              Icons.send_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      ],
    );
  }

  /// Barra normale: emoji + allegato + testo + send/mic
  Widget _buildNormalInputRow() {
    final canSend = _hasText || _pendingFile != null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _inputIconButton(
          icon: _showEmojiPicker
              ? Icons.keyboard_rounded
              : Icons.emoji_emotions_outlined,
          onTap: _toggleEmojiPicker,
        ),
        _inputIconButton(
          icon: Icons.attach_file_rounded,
          onTap: _showAttachMenu,
        ),
        Expanded(
          child: Container(
            constraints: const BoxConstraints(maxHeight: 120),
            decoration: BoxDecoration(
              color: AppConstants.primaryBlack,
              borderRadius: BorderRadius.circular(24),
            ),
            child: TextField(
              controller: _messageController,
              focusNode: _focusNode,
              decoration: const InputDecoration(
                hintText: 'Scrivi un messaggio...',
                hintStyle: TextStyle(color: AppConstants.textTertiary),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
              style: const TextStyle(
                color: AppConstants.textPrimary,
                fontSize: 15,
              ),
              textCapitalization: TextCapitalization.sentences,
              maxLines: 5,
              minLines: 1,
              keyboardAppearance: Brightness.dark,
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Send button (testo/allegato) oppure mic button (long press)
        if (canSend)
          GestureDetector(
            onTap: _sendMessage,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF42A5F5), Color(0xFF1565C0)],
                ),
              ),
              child: _isSending
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(
                      Icons.send_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
            ),
          )
        else
          GestureDetector(
            onLongPressStart: (_) => _startRecording(),
            onLongPressEnd: (_) => _stopRecording(),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppConstants.divider,
              ),
              child: const Icon(
                Icons.mic_rounded,
                color: AppConstants.textSecondary,
                size: 22,
              ),
            ),
          ),
      ],
    );
  }

  Widget _inputIconButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: AppConstants.textSecondary, size: 22),
        ),
      ),
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _formatDateLabel(DateTime date) {
    final now = DateTime.now();
    if (_isSameDay(date, now)) return 'Oggi';
    if (_isSameDay(date, now.subtract(const Duration(days: 1)))) {
      return 'Ieri';
    }
    return DateFormat('d MMM', 'it').format(date);
  }

  String _formatTime(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

// ─── Picker galleria interna Invisible ───────────────────────────────────────

class _InvisibleGalleryPicker extends StatefulWidget {
  const _InvisibleGalleryPicker();

  @override
  State<_InvisibleGalleryPicker> createState() => _InvisibleGalleryPickerState();
}

class _InvisibleGalleryPickerState extends State<_InvisibleGalleryPicker> {
  final _service = MediaLibraryService();
  List<File> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await _service.getLibraryItems();
    if (mounted) setState(() { _items = items; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.backgroundBlack,
      appBar: AppBar(
        backgroundColor: AppConstants.surfaceBlack,
        title: const Text('Scegli dalla galleria'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.photo_library_outlined, size: 64, color: AppConstants.textTertiary),
                      const SizedBox(height: 16),
                      const Text(
                        'Nessun media nella galleria',
                        style: TextStyle(color: AppConstants.textSecondary, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Importa foto/video dalla schermata Media',
                        style: TextStyle(color: AppConstants.textTertiary, fontSize: 13),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(4),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 3,
                    mainAxisSpacing: 3,
                  ),
                  itemCount: _items.length,
                  itemBuilder: (_, i) {
                    final file = _items[i];
                    return GestureDetector(
                      onTap: () => Navigator.of(context).pop(file),
                      child: _GalleryPickerTile(file: file, service: _service),
                    );
                  },
                ),
    );
  }
}

class _GalleryPickerTile extends StatefulWidget {
  final File file;
  final MediaLibraryService service;
  const _GalleryPickerTile({required this.file, required this.service});

  @override
  State<_GalleryPickerTile> createState() => _GalleryPickerTileState();
}

class _GalleryPickerTileState extends State<_GalleryPickerTile> {
  Uint8List? _thumb;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    if (widget.service.isVideoFile(widget.file.path)) _loadThumb();
  }

  Future<void> _loadThumb() async {
    final t = await VideoThumbnail.thumbnailData(
      video: widget.file.path,
      imageFormat: ImageFormat.JPEG,
      maxWidth: 200,
      quality: 70,
    );
    if (mounted) setState(() { _thumb = t; _loaded = true; });
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.service.isVideoFile(widget.file.path);
    Widget content;
    if (widget.service.isImageFile(widget.file.path)) {
      content = Image.file(widget.file, fit: BoxFit.cover);
    } else if (isVideo) {
      if (_loaded && _thumb != null) {
        content = Image.memory(_thumb!, fit: BoxFit.cover);
      } else if (_loaded) {
        content = const Center(child: Icon(Icons.videocam_rounded, color: AppConstants.textTertiary, size: 32));
      } else {
        content = const Center(child: CircularProgressIndicator(strokeWidth: 2));
      }
    } else {
      content = const Center(child: Icon(Icons.insert_drive_file_rounded, color: AppConstants.textTertiary, size: 32));
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
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.55),
                ),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
              ),
            ),
        ],
      ),
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:invisible/core/network/invisible_client.dart';
import 'package:invisible/core/network/mesh_vpn_service.dart';
import 'package:invisible/core/services/call_log_service.dart';
import 'package:invisible/core/services/call_service.dart';
import 'package:invisible/core/services/session_service.dart';
import 'package:invisible/utils/constants.dart';
import 'package:invisible/features/auth/screens/not_activated_screen.dart';
import 'package:invisible/features/calls/screens/call_screen.dart';
import 'package:invisible/features/calls/screens/calls_list_screen.dart';
import 'package:invisible/features/calls/screens/incoming_call_screen.dart';
import 'package:invisible/features/contacts/screens/contacts_screen.dart';
import 'package:invisible/features/chat/screens/chats_list_screen.dart';
import 'package:invisible/features/media_gallery/screens/media_gallery_screen.dart';
import 'package:invisible/features/settings/screens/settings_screen.dart';
import 'package:invisible/models/call_log_entry.dart';
import 'package:uuid/uuid.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 1;
  StreamSubscription<IncomingCallInfo>? _incomingCallSub;
  StreamSubscription<void>? _notAuthorizedSub;
  StreamSubscription<void>? _meshNotAuthorizedSub;

  @override
  void initState() {
    super.initState();
    SessionService().startSession();
    CallService().startListening();
    _incomingCallSub = CallService().incomingCallStream.listen(_onIncomingCall);
    _notAuthorizedSub = InvisibleClient().notAuthorizedStream.listen((_) => _onNotAuthorized());
    _meshNotAuthorizedSub = MeshVpnService().notAuthorizedStream.listen((_) => _onNotAuthorized());
    // Connette mesh VPN dopo che la schermata è visibile (Activity in foreground)
    WidgetsBinding.instance.addPostFrameCallback((_) => _connectMesh());
  }

  void _onNotAuthorized() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const NotActivatedScreen()),
      (_) => false,
    );
  }

  void _connectMesh() {
    if (MeshVpnService().status == MeshStatus.connected) return;
    MeshVpnService().connect(AppConstants.meshHttpUrl).then((_) {
      debugPrint('[MESH] Connesso da HomeScreen');
    }).catchError((e) {
      debugPrint('[MESH] Errore: $e');
    });
  }

  void _onIncomingCall(IncomingCallInfo info) {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => IncomingCallScreen(
          callInfo: info,
          onAccept: () => _acceptCall(info),
          onReject: () => _rejectCall(info),
        ),
      ),
    );
  }

  Future<void> _acceptCall(IncomingCallInfo info) async {
    Navigator.of(context).pop(); // chiude IncomingCallScreen
    final ok = await CallService().acceptCall(info);
    if (!ok || !mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CallScreen(
          contactName: info.callerName,
          isVideo: info.isVideo,
          isOutgoing: false,
        ),
      ),
    );
  }

  void _rejectCall(IncomingCallInfo info) {
    CallService().rejectCall(info.callId, info.callerIdentityHash);
    // Salva nel registro come chiamata rifiutata
    CallLogService().saveEntry(CallLogEntry(
      id: const Uuid().v4(),
      contactName: info.callerName,
      callType: info.isVideo ? CallType.video : CallType.audio,
      direction: CallDirection.incoming,
      status: CallStatus.rejected,
      durationSeconds: 0,
      startedAt: DateTime.now(),
    ));
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _incomingCallSub?.cancel();
    _notAuthorizedSub?.cancel();
    _meshNotAuthorizedSub?.cancel();
    super.dispose();
  }

  final List<Widget> _screens = const [
    ContactsScreen(),
    ChatsListScreen(),
    CallsListScreen(),
    MediaGalleryScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: _GradientNavBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
      ),
    );
  }
}

class _GradientNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _GradientNavBar({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0D),
        border: Border(
          top: BorderSide(
            color: AppConstants.primaryBlue.withValues(alpha: 0.18),
            width: 0.5,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: AppConstants.primaryBlue.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              Expanded(child: _NavItem(icon: Icons.people_outline_rounded, activeIcon: Icons.people_rounded, label: 'Contatti', index: 0, currentIndex: currentIndex, onTap: onTap)),
              Expanded(child: _NavItem(icon: Icons.chat_bubble_outline_rounded, activeIcon: Icons.chat_bubble_rounded, label: 'Chat', index: 1, currentIndex: currentIndex, onTap: onTap)),
              Expanded(child: _NavItem(icon: Icons.phone_outlined, activeIcon: Icons.phone_rounded, label: 'Chiamate', index: 2, currentIndex: currentIndex, onTap: onTap)),
              Expanded(child: _NavItem(icon: Icons.photo_library_outlined, activeIcon: Icons.photo_library_rounded, label: 'Media', index: 3, currentIndex: currentIndex, onTap: onTap)),
              Expanded(child: _NavItem(icon: Icons.settings_outlined, activeIcon: Icons.settings_rounded, label: 'Impost.', index: 4, currentIndex: currentIndex, onTap: onTap)),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int index;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.index,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = index == currentIndex;
    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive ? activeIcon : icon,
              color: isActive ? AppConstants.primaryBlue : AppConstants.textTertiary,
              size: 24,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive ? AppConstants.primaryBlue : AppConstants.textTertiary,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }
}

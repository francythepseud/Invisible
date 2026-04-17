import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:invisible/core/network/invisible_client.dart';
import 'package:invisible/core/network/mesh_vpn_service.dart';
import 'package:invisible/core/services/notification_service.dart';
import 'package:invisible/core/services/profile_service.dart';
import 'package:invisible/core/services/security_settings_service.dart';
import 'package:invisible/core/services/session_service.dart';
import 'package:invisible/features/auth/screens/login_screen.dart';
import 'package:invisible/utils/constants.dart';
import 'package:invisible/core/services/panic_service.dart';
import 'package:invisible/features/auth/screens/welcome_screen.dart';
import 'package:invisible/models/user_credentials.dart';
import 'package:invisible/utils/navigator_key.dart';
import 'qr_code_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _profileService          = ProfileService();
  final _notifService            = NotificationService();
  final _securitySettingsService = SecuritySettingsService();

  RelayStatus _relayStatus = InvisibleClient().status;
  MeshStatus  _meshStatus  = MeshVpnService().status;
  String? _qrData;
  String? _activationCode;

  // Notifiche
  bool _notifEnabled            = false;
  NotifSound _notifSound        = NotifSound.predefinito;
  final _notifMessageController = TextEditingController();

  // Privacy
  bool _screenshotPrevention = true;
  int  _autoLockMinutes      = 5;
  int  _msgExpiryDays        = 0;

  // ignore: unused_field
  StreamSubscription<RelayStatus>? _relaySubscription;
  // ignore: unused_field
  StreamSubscription<MeshStatus>?  _meshSubscription;

  bool get _isOnline        => _relayStatus == RelayStatus.connected;
  bool get _isMeshConnected => _meshStatus  == MeshStatus.connected;
  String? get _meshIp       => MeshVpnService().assignedIp;

  @override
  void initState() {
    super.initState();
    _relaySubscription = InvisibleClient().statusStream.listen((s) {
      if (mounted) setState(() => _relayStatus = s);
    });
    _meshSubscription = MeshVpnService().statusStream.listen((s) {
      if (mounted) setState(() => _meshStatus = s);
    });
    _loadQrData();
    _loadActivationCode();
    _loadNotifSettings();
    _loadPrivacySettings();
  }

  // ── Load ──────────────────────────────────────────────────────────────────

  Future<void> _loadNotifSettings() async {
    final enabled = await _notifService.isEnabled();
    final message = await _notifService.getMessage();
    final sound   = await _notifService.getSound();
    if (!mounted) return;
    setState(() {
      _notifEnabled = enabled;
      _notifSound   = sound;
      _notifMessageController.text = message;
    });
  }

  Future<void> _loadPrivacySettings() async {
    final screenshot = await _securitySettingsService.getScreenshotPrevention();
    final autoLock   = await _securitySettingsService.getAutoLockMinutes();
    final expiry     = await _securitySettingsService.getMessageExpirationDays();
    if (!mounted) return;
    setState(() {
      _screenshotPrevention = screenshot;
      _autoLockMinutes      = autoLock;
      _msgExpiryDays        = expiry;
    });
  }

  Future<void> _reconnectMesh() async {
    if (_meshStatus == MeshStatus.connecting) return;
    setState(() => _meshStatus = MeshStatus.connecting);
    try {
      await MeshVpnService().connect(AppConstants.meshHttpUrl);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Mesh: ${e.toString().replaceAll('Exception: ', '')}'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppConstants.error,
        ));
      }
    }
  }

  Future<void> _loadActivationCode() async {
    final keys = await _profileService.getCurrentCryptoKeys();
    if (keys == null || !mounted) return;
    final k = keys.identityKeyPublic;
    setState(() => _activationCode = k.length > 32 ? k.substring(k.length - 32) : k);
  }

  Future<void> _loadQrData() async {
    final keys = await _profileService.getCurrentCryptoKeys();
    if (keys == null || !mounted) return;
    setState(() => _qrData = jsonEncode({
      'v': 1, 'mk': keys.masterKeyPublic, 'ik': keys.identityKeyPublic,
      'spk': keys.signedPreKeyPublic, 'sig': keys.signedPreKeySignature,
    }));
  }

  // ── Notifiche ─────────────────────────────────────────────────────────────

  Future<void> _changeSound(NotifSound sound) async {
    await _notifService.setSound(sound);
    if (mounted) setState(() => _notifSound = sound);
  }

  Future<void> _toggleNotif(bool value) async {
    if (value) {
      final granted = await _notifService.requestPermission();
      if (!granted && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Permesso notifiche non concesso'),
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }
    }
    await _notifService.setEnabled(value);
    if (mounted) setState(() => _notifEnabled = value);
  }

  Future<void> _saveNotifMessage(String value) async =>
      _notifService.setMessage(value);

  // ── Privacy ───────────────────────────────────────────────────────────────

  Future<void> _toggleScreenshotPrevention(bool value) async {
    // setScreenshotPrevention salva E applica subito il FLAG_SECURE via MethodChannel
    await _securitySettingsService.setScreenshotPrevention(value);
    if (mounted) setState(() => _screenshotPrevention = value);
  }

  Future<void> _setAutoLock(int minutes) async {
    await _securitySettingsService.setAutoLockMinutes(minutes);
    if (mounted) setState(() => _autoLockMinutes = minutes);
  }

  Future<void> _setMsgExpiry(int days) async {
    await _securitySettingsService.setMessageExpirationDays(days);
    if (mounted) setState(() => _msgExpiryDays = days);
  }

  // ── Panic wipe ────────────────────────────────────────────────────────────

  Future<void> _panicWipe() async {
    final passwordController = TextEditingController();
    final passwordOk = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppConstants.surfaceBlack,
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: AppConstants.error, size: 22),
          SizedBox(width: 10),
          Text('Conferma password', style: TextStyle(fontSize: 17)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Inserisci la tua password per autorizzare la cancellazione di tutti i dati.',
              style: TextStyle(color: AppConstants.textSecondary, fontSize: 13, height: 1.5)),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController, obscureText: true, autofocus: true,
              style: const TextStyle(color: AppConstants.textPrimary),
              decoration: InputDecoration(
                hintText: 'Password',
                hintStyle: const TextStyle(color: AppConstants.textTertiary),
                filled: true, fillColor: AppConstants.cardBlack,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppConstants.divider)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppConstants.divider)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppConstants.error)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppConstants.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continua', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (passwordOk != true) return;

    final profile = _profileService.currentProfile;
    if (profile == null) return;
    try {
      await _profileService.login(
        UserCredentials(username: profile.username, password: passwordController.text),
      );
    } catch (_) {
      passwordController.dispose();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Attenzione: password errata'),
          backgroundColor: AppConstants.error,
        ));
      }
      return;
    }
    passwordController.dispose();
    if (!mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppConstants.surfaceBlack,
        title: const Row(children: [
          Icon(Icons.delete_forever_rounded, color: AppConstants.error, size: 22),
          SizedBox(width: 10),
          Text('Sei sicuro?', style: TextStyle(fontSize: 17)),
        ]),
        content: const Text(
          'Tutti i dati verranno eliminati definitivamente:\n\n'
          '• Profili e password\n• Contatti e messaggi\n'
          '• Chiavi crittografiche\n• Foto e video\n\n'
          'Questa azione è irreversibile.',
          style: TextStyle(color: AppConstants.textSecondary, fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppConstants.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('CANCELLA TUTTO',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    await PanicService().wipeAll();
    if (mounted) {
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
        (route) => false,
      );
    }
  }

  // ── Logout ────────────────────────────────────────────────────────────────

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Sei sicuro di voler uscire?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annulla')),
          ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Esci')),
        ],
      ),
    );
    if (confirm == true) {
      try { await SessionService().endSession(); } catch (_) {}
      try { await _profileService.logout(); } catch (_) {}
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final profile  = _profileService.currentProfile;
    final username = profile?.username ?? 'Sconosciuto';
    final initial  = username.isNotEmpty ? username[0].toUpperCase() : '?';

    return Scaffold(
      backgroundColor: AppConstants.backgroundBlack,
      appBar: AppBar(
        title: const Text('Impostazioni'),
        backgroundColor: AppConstants.backgroundBlack,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: Color(0xFF1E1E1E)),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [

          // ── Profilo ───────────────────────────────────────────────────────
          _buildProfileHeader(username, initial),

          // ── QR Code ───────────────────────────────────────────────────────
          _buildSectionLabel('IL MIO QR CODE'),
          _buildQrCard(),

          // ── Notifiche ─────────────────────────────────────────────────────
          _buildSectionLabel('NOTIFICHE'),
          _buildNotificationCard(),

          // ── Privacy & Sicurezza ───────────────────────────────────────────
          _buildSectionLabel('PRIVACY & SICUREZZA'),
          _buildPrivacyCard(),

          // ── Stato Rete ────────────────────────────────────────────────────
          _buildSectionLabel('STATO RETE'),
          _buildNetworkCard(),

          // ── Codice Attivazione ────────────────────────────────────────────
          _buildSectionLabel('CODICE ATTIVAZIONE'),
          _buildActivationCard(),

          // ── Zona di Pericolo ──────────────────────────────────────────────
          _buildSectionLabel('ZONA DI PERICOLO'),
          _buildPanicCard(),

          const SizedBox(height: 8),

          // ── Account ───────────────────────────────────────────────────────
          _buildSectionLabel('ACCOUNT'),
          _buildLogoutButton(),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SECTION BUILDERS
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildProfileHeader(String username, String initial) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Row(children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [AppConstants.primaryBlue, AppConstants.darkBlue],
            ),
            boxShadow: [BoxShadow(
              color: AppConstants.primaryBlue.withValues(alpha: 0.4),
              blurRadius: 16, spreadRadius: 1,
            )],
          ),
          child: Center(child: Text(initial, style: const TextStyle(
            fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white,
          ))),
        ),
        const SizedBox(width: 16),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(username, style: const TextStyle(
            fontSize: 20, fontWeight: FontWeight.bold, color: AppConstants.textPrimary,
          )),
          const SizedBox(height: 4),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppConstants.primaryBlue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('Invisible', style: TextStyle(
                fontSize: 11, color: AppConstants.primaryBlue, fontWeight: FontWeight.w600,
              )),
            ),
            const SizedBox(width: 8),
            _GlowDot(active: _isOnline),
            const SizedBox(width: 4),
            Text(
              _isOnline ? 'online' : 'offline',
              style: TextStyle(
                fontSize: 11,
                color: _isOnline ? AppConstants.success : AppConstants.textTertiary,
              ),
            ),
          ]),
        ]),
      ]),
    );
  }

  Widget _buildQrCard() {
    return _card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(children: [
        GestureDetector(
          onTap: _qrData == null ? null : () =>
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QRCodeScreen())),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: _qrData == null
                ? const SizedBox(height: 180, child: Center(child: CircularProgressIndicator()))
                : Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white, borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(
                        color: AppConstants.primaryBlue.withValues(alpha: 0.25),
                        blurRadius: 20, spreadRadius: 2,
                      )],
                    ),
                    child: QrImageView(
                      data: _qrData!, version: QrVersions.auto, size: 180,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square, color: Colors.black),
                    ),
                  ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text('Fai scansionare per aggiungere il tuo contatto',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppConstants.textTertiary)),
        ),
        if (_qrData != null) ...[
          const Divider(height: 1, color: AppConstants.divider),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(children: [
              Expanded(child: TextButton.icon(
                icon: const Icon(Icons.share_rounded, size: 18),
                label: const Text('Condividi'),
                onPressed: () => Share.share(_qrData!, subject: 'Invisible — Chiave di contatto'),
              )),
              Container(width: 1, height: 32, color: AppConstants.divider),
              Expanded(child: TextButton.icon(
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copia'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _qrData!));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Chiave copiata negli appunti'),
                    behavior: SnackBarBehavior.floating,
                  ));
                },
              )),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _buildNotificationCard() {
    return _card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _settingRow(
          icon: Icons.notifications_none_rounded,
          title: 'Ricevi notifiche',
          subtitle: 'Avviso discreto senza mostrare mittente o contenuto',
          trailing: Switch(value: _notifEnabled, onChanged: _toggleNotif,
            activeThumbColor: AppConstants.primaryBlue),
        ),
        if (_notifEnabled) ...[
          const Divider(height: 1, color: AppConstants.divider),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _label('TESTO DELLA NOTIFICA'),
              const SizedBox(height: 8),
              TextField(
                controller: _notifMessageController,
                style: const TextStyle(color: AppConstants.textPrimary, fontSize: 14),
                maxLength: 80,
                decoration: InputDecoration(
                  counterText: '',
                  hintText: 'Hai ricevuto un messaggio',
                  hintStyle: const TextStyle(color: AppConstants.textTertiary, fontSize: 14),
                  filled: true, fillColor: AppConstants.surfaceBlack,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppConstants.divider)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppConstants.divider)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppConstants.primaryBlue)),
                ),
                onSubmitted: _saveNotifMessage,
                onTapOutside: (_) => _saveNotifMessage(_notifMessageController.text),
              ),
            ]),
          ),
          const Divider(height: 1, color: AppConstants.divider),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _label('SUONO'),
              const SizedBox(height: 10),
              Row(children: [
                _buildSoundChip(label: 'Predefinito', icon: Icons.volume_up_rounded,
                  value: NotifSound.predefinito),
                const SizedBox(width: 8),
                _buildSoundChip(label: 'Vibrazione', icon: Icons.vibration_rounded,
                  value: NotifSound.soloVibrazione),
                const SizedBox(width: 8),
                _buildSoundChip(label: 'Silenzioso', icon: Icons.notifications_off_rounded,
                  value: NotifSound.silenzioso),
              ]),
            ]),
          ),
        ],
        const Divider(height: 1, color: AppConstants.divider),
        _infoHint('Le notifiche non rivelano mittente né contenuto — nessun dato inviato a Google o terze parti.'),
      ]),
    );
  }

  Widget _buildPrivacyCard() {
    return _card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Screenshot prevention ────────────────────────────────────────
        _settingRow(
          icon: Icons.screenshot_monitor_rounded,
          iconColor: AppConstants.primaryBlue,
          title: 'Blocca screenshot',
          subtitle: _screenshotPrevention
              ? 'Attivo — nessuno può catturare lo schermo'
              : 'Disattivo — screenshot permessi',
          trailing: Switch(value: _screenshotPrevention,
            onChanged: _toggleScreenshotPrevention,
            activeThumbColor: AppConstants.primaryBlue),
        ),
        _infoHint('Consigliato ON. Impedisce screenshot, screen recording e anteprima nelle app recenti (Android).'),

        const Divider(height: 1, color: AppConstants.divider),

        // ── Auto-lock ────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(children: [
            _iconBox(Icons.lock_clock_rounded, AppConstants.primaryBlue),
            const SizedBox(width: 12),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Blocco automatico',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500,
                  color: AppConstants.textPrimary)),
              Text('Richiede login dopo inattività in background',
                style: TextStyle(fontSize: 12, color: AppConstants.textTertiary)),
            ])),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: _optionChips<int>(
            options: const [0, 1, 5, 10, 30],
            selected: _autoLockMinutes,
            label: (v) => v == 0 ? 'Mai' : '$v min',
            onSelected: _setAutoLock,
          ),
        ),
        _infoHint('Consigliato: 5 min. Se esci dall\'app per il tempo impostato, dovrai reinserire la password.'),

        const Divider(height: 1, color: AppConstants.divider),

        // ── Scadenza messaggi ────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(children: [
            _iconBox(Icons.timer_off_rounded, AppConstants.warning),
            const SizedBox(width: 12),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Scadenza messaggi',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500,
                  color: AppConstants.textPrimary)),
              Text('Elimina automaticamente i messaggi vecchi',
                style: TextStyle(fontSize: 12, color: AppConstants.textTertiary)),
            ])),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: _optionChips<int>(
            options: const [0, 1, 7, 30, 90],
            selected: _msgExpiryDays,
            label: (v) => v == 0 ? 'Mai' : v == 1 ? '1 giorno' : '$v giorni',
            onSelected: _setMsgExpiry,
            activeColor: AppConstants.warning,
          ),
        ),
        _infoHint('I messaggi più vecchi della soglia vengono eliminati definitivamente al prossimo avvio. '
            'Nessun recupero possibile.'),
      ]),
    );
  }

  Widget _buildNetworkCard() {
    final borderColor = _isOnline
        ? AppConstants.success.withValues(alpha: 0.35)
        : AppConstants.divider;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: AppConstants.cardBlack,
          borderRadius: BorderRadius.circular(AppConstants.radiusLarge),
          border: Border.all(color: borderColor),
        ),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(children: [
              _GlowDot(active: _isOnline),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  _isOnline ? 'ONLINE' : 'OFFLINE',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                    letterSpacing: 1.3,
                    color: _isOnline ? AppConstants.success : AppConstants.textTertiary),
                ),
                if (_isMeshConnected && _meshIp != null)
                  Text('IP mesh: $_meshIp', style: const TextStyle(
                    fontSize: 11, color: AppConstants.textTertiary, fontFamily: 'monospace')),
              ]),
              const Spacer(),
              _SubBadge(label: 'Relay', active: _relayStatus == RelayStatus.connected,
                loading: _relayStatus == RelayStatus.connecting ||
                    _relayStatus == RelayStatus.reconnecting),
              const SizedBox(width: 6),
              _SubBadge(label: 'Mesh', active: _isMeshConnected,
                loading: _meshStatus == MeshStatus.connecting),
              if (!_isMeshConnected && _meshStatus != MeshStatus.connecting) ...[
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: _reconnectMesh,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppConstants.primaryBlue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppConstants.primaryBlue.withValues(alpha: 0.4)),
                    ),
                    child: const Text('Riconnetti', style: TextStyle(
                        fontSize: 11, color: AppConstants.primaryBlue, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ]),
          ),
          const Divider(height: 1, color: AppConstants.divider),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _FeatureChip(icon: Icons.chat_bubble_rounded, label: 'Messaggi', active: _isOnline),
                _FeatureChip(icon: Icons.call_rounded, label: 'Chiamate', active: _isMeshConnected),
                _FeatureChip(icon: Icons.attach_file_rounded, label: 'File', active: _isOnline),
                _FeatureChip(icon: Icons.shield_rounded, label: 'Mesh VPN', active: _isMeshConnected),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildActivationCard() {
    final code = _activationCode;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: AppConstants.cardBlack,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppConstants.primaryBlue.withValues(alpha: 0.2)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(
            'Codice da inviare all\'amministratore per attivare l\'app',
            style: TextStyle(fontSize: 12, color: AppConstants.textTertiary),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppConstants.surfaceBlack,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              code ?? '...',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: AppConstants.primaryBlue,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: code == null ? null : () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Codice copiato'),
                behavior: SnackBarBehavior.floating,
                duration: Duration(seconds: 1),
              ));
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppConstants.primaryBlue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppConstants.primaryBlue.withValues(alpha: 0.3)),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.copy_rounded, size: 14, color: AppConstants.primaryBlue),
                SizedBox(width: 6),
                Text('Copia codice', style: TextStyle(fontSize: 12, color: AppConstants.primaryBlue, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildPanicCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: AppConstants.error.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppConstants.error.withValues(alpha: 0.35)),
        ),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppConstants.error.withValues(alpha: 0.15),
                ),
                child: const Icon(Icons.emergency_rounded, color: AppConstants.error, size: 22),
              ),
              const SizedBox(width: 14),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Panic Button',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                    color: AppConstants.error)),
                SizedBox(height: 2),
                Text('Cancella tutti i dati immediatamente',
                  style: TextStyle(fontSize: 12, color: AppConstants.textTertiary)),
              ])),
            ]),
          ),
          const Divider(height: 1, color: AppConstants.divider),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Text(
              'Elimina definitivamente profili, chiavi crittografiche, messaggi, contatti e media. '
              'L\'app tornerà allo stato iniziale. Richiede la tua password.',
              style: const TextStyle(fontSize: 12, color: AppConstants.textTertiary, height: 1.5),
            ),
          ),
          const Divider(height: 1, color: AppConstants.divider),
          GestureDetector(
            onTap: _panicWipe,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppConstants.error.withValues(alpha: 0.12),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
              ),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.delete_forever_rounded, color: AppConstants.error, size: 20),
                SizedBox(width: 8),
                Text('CANCELLA TUTTI I DATI', style: TextStyle(
                  color: AppConstants.error, fontSize: 14,
                  fontWeight: FontWeight.w700, letterSpacing: 0.5)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildLogoutButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: GestureDetector(
        onTap: _logout,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            color: AppConstants.surfaceBlack,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppConstants.divider),
          ),
          child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.logout_rounded, color: AppConstants.textSecondary, size: 18),
            SizedBox(width: 8),
            Text('Logout', style: TextStyle(
              color: AppConstants.textSecondary, fontSize: 15, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MICRO-WIDGET HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(text, style: const TextStyle(
        fontSize: 11, fontWeight: FontWeight.w700,
        color: AppConstants.textTertiary, letterSpacing: 1.0,
      )),
    );
  }

  Widget _card({required Widget child, EdgeInsetsGeometry? margin}) {
    return Padding(
      padding: margin ?? const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: AppConstants.cardBlack,
          borderRadius: BorderRadius.circular(AppConstants.radiusLarge),
          border: Border.all(color: AppConstants.divider),
        ),
        child: child,
      ),
    );
  }

  Widget _settingRow({
    required IconData icon,
    Color? iconColor,
    required String title,
    required String subtitle,
    required Widget trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(children: [
        _iconBox(icon, iconColor ?? AppConstants.textSecondary),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500,
            color: AppConstants.textPrimary)),
          Text(subtitle, style: const TextStyle(fontSize: 12, color: AppConstants.textTertiary)),
        ])),
        trailing,
      ]),
    );
  }

  Widget _iconBox(IconData icon, Color color) {
    return Container(
      width: 36, height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }

  Widget _label(String text) {
    return Text(text, style: const TextStyle(
      fontSize: 11, color: AppConstants.textTertiary,
      fontWeight: FontWeight.w600, letterSpacing: 0.5,
    ));
  }

  Widget _infoHint(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.info_outline_rounded, size: 13, color: AppConstants.primaryBlue),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: const TextStyle(
          fontSize: 11, color: AppConstants.textTertiary, height: 1.5))),
      ]),
    );
  }

  Widget _optionChips<T>({
    required List<T> options,
    required T selected,
    required String Function(T) label,
    required ValueChanged<T> onSelected,
    Color? activeColor,
  }) {
    final color = activeColor ?? AppConstants.primaryBlue;
    return Wrap(spacing: 8, runSpacing: 8, children: options.map((v) {
      final isSel = v == selected;
      return GestureDetector(
        onTap: () => onSelected(v),
        child: AnimatedContainer(
          duration: AppConstants.animationFast,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: isSel ? color.withValues(alpha: 0.15) : AppConstants.surfaceBlack,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isSel ? color.withValues(alpha: 0.7) : AppConstants.divider),
          ),
          child: Text(label(v), style: TextStyle(
            fontSize: 13,
            fontWeight: isSel ? FontWeight.w600 : FontWeight.normal,
            color: isSel ? color : AppConstants.textTertiary,
          )),
        ),
      );
    }).toList());
  }

  Widget _buildSoundChip({
    required String label,
    required IconData icon,
    required NotifSound value,
  }) {
    final selected = _notifSound == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => _changeSound(value),
        child: AnimatedContainer(
          duration: AppConstants.animationFast,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? AppConstants.primaryBlue.withValues(alpha: 0.15)
                : AppConstants.surfaceBlack,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? AppConstants.primaryBlue.withValues(alpha: 0.6)
                  : AppConstants.divider),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18,
              color: selected ? AppConstants.primaryBlue : AppConstants.textTertiary),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              color: selected ? AppConstants.primaryBlue : AppConstants.textTertiary,
            )),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stateless helper widgets
// ─────────────────────────────────────────────────────────────────────────────

class _GlowDot extends StatelessWidget {
  final bool active;
  const _GlowDot({required this.active});

  @override
  Widget build(BuildContext context) {
    final color = active ? AppConstants.success : AppConstants.textTertiary;
    return Container(
      width: 10, height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle, color: color,
        boxShadow: active ? [BoxShadow(
          color: AppConstants.success.withValues(alpha: 0.6),
          blurRadius: 8, spreadRadius: 1,
        )] : null,
      ),
    );
  }
}

class _SubBadge extends StatelessWidget {
  final String label;
  final bool active;
  final bool loading;
  const _SubBadge({required this.label, required this.active, this.loading = false});

  @override
  Widget build(BuildContext context) {
    final color = loading ? Colors.orange
        : active ? AppConstants.success
        : AppConstants.textTertiary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(
          fontSize: 10, fontWeight: FontWeight.w600, color: color, letterSpacing: 0.3)),
      ]),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  const _FeatureChip({required this.icon, required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    final color = active ? AppConstants.success : AppConstants.textTertiary;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1), shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Icon(icon, size: 20, color: color),
      ),
      const SizedBox(height: 5),
      Text(label, style: TextStyle(fontSize: 10,
        color: active ? AppConstants.textSecondary : AppConstants.textTertiary)),
    ]);
  }
}

import 'dart:async';
import 'package:invisible/core/network/invisible_client.dart';
import 'package:invisible/models/contact.dart';

/// Traccia quali contatti sono online in base agli eventi presenza del relay.
///
/// Il relay invia {"type":"presence","from":"shortHash","payload":"online|offline"}.
/// shortHash = ultimi 32 caratteri della identity key base64.
class PresenceService {
  static final PresenceService _instance = PresenceService._internal();
  factory PresenceService() => _instance;
  PresenceService._internal();

  final _client = InvisibleClient();
  final _online = <String>{}; // set di shortHash online
  final _controller = StreamController<String>.broadcast(); // emette userId cambiato

  StreamSubscription<PresenceEvent>? _sub;

  /// Avvia l'ascolto degli eventi presenza.
  void start() {
    _sub?.cancel();
    _sub = _client.presenceStream.listen((event) {
      if (event.online) {
        _online.add(event.userId);
      } else {
        _online.remove(event.userId);
      }
      _controller.add(event.userId);
    });
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _online.clear();
  }

  /// Stream che emette l'userId ogni volta che il suo stato cambia.
  Stream<String> get changes => _controller.stream;

  /// Restituisce true se il contatto è online.
  bool isOnline(Contact contact) {
    if (contact.identityKey == null) return false;
    final key = contact.identityKey!;
    final hash = key.length > 32 ? key.substring(key.length - 32) : key;
    return _online.contains(hash);
  }
}

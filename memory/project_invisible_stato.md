---
name: Invisible - Stato progetto e TODO
description: Stato build, bug risolti, funzionalità testate e da completare
type: project
---

Chiamate audio iPhone ↔ Android funzionanti confermato 2026-04-09.

**Why:** Fix critico al protocollo signaling — server Go usava messaggi `offer/answer/ice/hangup` ma il client Flutter mandava `signal` con `signal_type`. Riscritto signaling_client.dart per usare il protocollo corretto.

**How to apply:** Non toccare il protocollo signaling senza verificare main.go del server.

## Funziona
- Messaggi E2E (Double Ratchet) iPhone ↔ Android
- Chiamate audio iPhone ↔ Android
- Segnalazione WebRTC (offer/answer/ICE)
- Echo cancellation / noise suppression attivi
- Registro chiamate (salvataggio)
- APK Android: `/Users/alessandrafoti/Downloads/Invisible/build/app/outputs/flutter-apk/app-release.apk`

## Bug risolti nel codice (da reinstallare)
- Schermo nero dopo hangup (doppio Navigator.pop eliminato)
- Lista chiamate vuota (ora salva anche chiamate con durata 0)
- Guard anti-self contact (non puoi aggiungere te stesso)

## Da fare
- Test videochiamata
- Mesh VPN su iPhone (richiede Apple Developer $99/anno → abilitare Network Extensions su developer.apple.com)
- Profilo persistente su iOS (salvare nel Keychain per sopravvivere ai reinstall)

## Note installazione
- Android: `adb install -r app-release.apk` (preserva dati)
- iOS: `ideviceinstaller install Runner.app` (attenzione: debug→release cancella dati)
- MAI usare `flutter run` su iOS se vuoi preservare il profilo
- Il profilo su iOS si perde se si passa da debug a release build

## Architettura chiavi
- shortHash = ultimi 32 caratteri della identity key Ed25519 base64
- Relay e signaling usano lo stesso schema shortHash
- QR payload: {v:1, mk: X25519 master, ik: Ed25519 identity, spk: signed pre-key, sig: firma spk}

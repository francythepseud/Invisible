# Invisible — Changelog

---

## v0.3.0 "Stable Core" — 2026-04-17

### Bug risolti

**Chat**
- Fix crash iOS all'avvio: `LocaleDataException` — aggiunto `initializeDateFormatting('it')` in `main.dart`
- Fix rettangolo rosso (ErrorWidget) nella lista messaggi: causato da `DateFormat('d MMM', 'it')` senza locale inizializzata
- Fix `PlatformException(DarwinAudioError)` su iOS: `AudioMessageBubble` crashava durante il preload audio su widget dispose; aggiunto `_disposed` flag e try-catch su tutte le chiamate player
- Fix `{"t":"rr"}` visibile come anteprima messaggio in lista chat: ora `refreshLastMessage` rilegge il DB dopo eliminazione receipt
- Fix contatore "2 messaggi non letti" alla prima apertura chat: `decrementUnreadCount` dopo eliminazione read receipt

**Chiamate**
- Fix crash altoparlante Android: `Helper.setSpeakerphoneOn` ora è `async` con try-catch
- Fix squillo mancante su iOS: ringtone WAV generato programmaticamente (dual-tone 480Hz+440Hz), salvato su file temporaneo e riprodotto via `DeviceFileSource` (BytesSource non supportato su iOS)
- Fix chiamata continua a squillare dopo che il chiamante riaggancia: `IncomingCallScreen` ora ascolta `callStateStream` e si chiude automaticamente su `CallState.ended`
- Aggiunto logging dettagliato su tutto il flusso chiamata: `getUserMedia`, `onTrack`, `acceptCall`, `toggleMute`, speaker

**Lista chiamate (iOS)**
- Fix rettangolo grigio su iOS: rimosso `ListTile` (che su Material3 iOS ignora `tileColor: transparent`), sostituito con layout custom `Padding + Row + Column`
- Fix background grigio sotto le card: aggiunto `Stack + ColoredBox` per sovrascrivere `canvasColor` iOS

**Generale**
- `main.dart`: crash handler che mostra l'errore su schermo in debug mode invece di chiudersi silenziosamente
- Fix `flutter run` su iOS 26: aggiunto `/opt/homebrew/bin` al PATH per trovare CocoaPods

---

## v0.2.0 "Encrypted Calls" — 2026-04-12

### Funzionalità aggiunte
- Registro chiamate con filtri (Tutte / In entrata / In uscita), swipe per eliminare, cancella tutto
- Schermata chiamata in arrivo con avatar pulsante e ringtone
- Logging chiamate: durata, tipo (audio/video), direzione, stato (completata/persa/rifiutata)

### Bug risolti
- Fix ListView invertita nella chat (WhatsApp-style): `reverse: true`, `scrollToBottom` usa `jumpTo(0)`
- Fix read receipt `{"t":"rr"}` salvata nel DB e mostrata in chat
- Fix contatore unread per read receipt: `receiveMessage` incrementava sempre, ora `decrementUnreadCount` corregge dopo rilevamento receipt
- Fix `Dismissible` su iOS: separati `background` (sinistra) e `secondaryBackground` (destra) per evitare rettangolo grigio

---

## v0.1.0 "First Working Build" — 2026-04-09 (backup git)

### Funzionalità base
- Autenticazione con profilo locale cifrato (SQLCipher)
- Chat E2E con Double Ratchet + X3DH
- Contatti con QR code
- Messaggi testo, immagini, file, audio, posizione
- Chiamate audio/video WebRTC cifrate (DTLS-SRTP)
- Rete mesh WireGuard
- Impostazioni sicurezza: auto-lock, screenshot prevention, scadenza messaggi
- Tema dark, supporto iOS e Android

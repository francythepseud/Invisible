# INVISIBLE — Documentazione di Rilascio
> Aggiornato: marzo 2026

---

## Indice
1. [Prerequisiti](#1-prerequisiti)
2. [Deploy del server VPS](#2-deploy-del-server-vps)
3. [Configurazione DNS e TLS](#3-configurazione-dns-e-tls)
4. [Certificate Pinning — attivazione](#4-certificate-pinning--attivazione)
5. [Build Android (APK / AAB)](#5-build-android-apk--aab)
6. [Build iOS (IPA / TestFlight)](#6-build-ios-ipa--testflight)
7. [Distribuzione agli utenti](#7-distribuzione-agli-utenti)
8. [Verifica funzionamento](#8-verifica-funzionamento)
9. [Aggiornamenti futuri](#9-aggiornamenti-futuri)
10. [Architettura di sicurezza — riepilogo](#10-architettura-di-sicurezza--riepilogo)
11. [Comandi utili di manutenzione](#11-comandi-utili-di-manutenzione)

---

## 1. Prerequisiti

### Macchina di sviluppo
- Flutter SDK ≥ 3.10.0 installato (`flutter --version`)
- Android Studio + Android SDK (per build Android)
- Xcode ≥ 15 su macOS (per build iOS)
- Git

### VPS
- Ubuntu 22.04 LTS (o Debian 12)
- Minimo 2 vCPU, 2 GB RAM, 20 GB SSD
- IP pubblico statico
- Porte aperte: **443** (HTTPS/WSS), **51820/UDP** (WireGuard)
- Accesso SSH con chiave

### Dominio
- Dominio registrato (es. `invisible-app.com`)
- Record DNS: `A` che punta all'IP del VPS
- DNS propagato (verificare con `nslookup tuodominio.com`)

---

## 2. Deploy del server VPS

```bash
# 1. Clona il progetto sul VPS
ssh utente@TUO_VPS_IP
git clone <repo> invisible
cd invisible/server

# 2. Esegui lo script di setup automatico
#    Lo script:
#    - Installa Docker + Docker Compose
#    - Genera chiavi WireGuard server
#    - Genera password PostgreSQL (casuale)
#    - Ottiene certificato TLS Let's Encrypt via certbot
#    - Crea il file .env con tutti i segreti
#    - Avvia tutti i microservizi con docker-compose up -d
bash setup.sh tuodominio.com

# 3. Verifica che i servizi siano tutti up
docker compose ps
# Tutti devono essere "healthy" o "running"
```

### Microservizi avviati dal setup.sh

| Servizio         | Porta interna | Funzione                                    |
|------------------|---------------|---------------------------------------------|
| `nginx`          | 443 (pubblico)| Reverse proxy TLS 1.3, rate limiting        |
| `relay`          | 8082          | Consegna messaggi E2E, coda 7 giorni        |
| `mesh-gateway`   | 8080          | Auth Ed25519 + assegna IP WireGuard         |
| `signaling`      | 8081          | Routing WebRTC SDP/ICE per chiamate         |
| `legal`          | 8083          | Registrazione accettazione ToS su PostgreSQL|
| `postgres`       | 5432 (interno)| Database ToS + profili (solo su rete Docker)|

### File .env generato da setup.sh
Dopo il setup troverai `server/.env` con:
```
DOMAIN=tuodominio.com
POSTGRES_PASSWORD=<generata casuale>
WG_SERVER_PRIVATE=<chiave WireGuard privata server>
WG_SERVER_PUBLIC=<chiave WireGuard pubblica server>  ← ti serve per il build Flutter
```

> **IMPORTANTE**: non committare mai `.env` su Git. È già in `.gitignore`.

---

## 3. Configurazione DNS e TLS

Il certificato TLS viene ottenuto automaticamente da `setup.sh` via **Let's Encrypt**.

### Rinnovo automatico (ogni 90 giorni)
Let's Encrypt con certbot si rinnova automaticamente. Verificare che il cron sia attivo:
```bash
systemctl status certbot.timer
# oppure
crontab -l | grep certbot
```

### Verificare il certificato
```bash
openssl s_client -connect tuodominio.com:443 </dev/null 2>/dev/null | openssl x509 -noout -dates -subject
```

---

## 4. Certificate Pinning — attivazione

**Da fare DOPO il deploy del server**, quando il certificato TLS è già installato.

### Step 1 — Ottieni il pin SPKI SHA-256 del server

```bash
# Eseguire dal tuo PC (non dal VPS)
# SPKI pin — sopravvive ai rinnovi Let's Encrypt se stessa chiave:
openssl s_client -connect tuodominio.com:443 </dev/null 2>/dev/null \
  | openssl x509 -pubkey -noout \
  | openssl pkey -pubin -outform der \
  | openssl dgst -sha256 -binary \
  | openssl enc -base64
# Esempio output: abc123DEF456==
```

```bash
# Pin del certificato completo (SHA-256 del DER) — per Dart PinnedHttpClient:
openssl s_client -connect tuodominio.com:443 </dev/null 2>/dev/null \
  | openssl x509 -outform der \
  | openssl dgst -sha256 \
  | awk '{print $2}'
# Esempio output: a1b2c3d4e5f6...
```

### Step 2 — Aggiorna network_security_config.xml (Android)

File: `android/app/src/main/res/xml/network_security_config.xml`

Decommentare e compilare il blocco:
```xml
<domain-config cleartextTrafficPermitted="false">
    <domain includeSubdomains="true">tuodominio.com</domain>
    <trust-anchors>
        <certificates src="system"/>
    </trust-anchors>
    <pin-set expiration="2027-06-01">
        <pin digest="SHA-256">SPKI_HASH_BASE64_PRINCIPALE==</pin>
        <pin digest="SHA-256">SPKI_HASH_BASE64_BACKUP==</pin>
    </pin-set>
</domain-config>
```

> **ATTENZIONE**: aggiornare la data `expiration` prima che scada, altrimenti l'app Android
> non si connetterà più al server. Aggiornare almeno 1 mese prima.

### Step 3 — Aggiorna il pin in iOS (da fare con Xcode)

Per iOS il cert pinning nativo richiede una implementazione con `NSURLSession` o TrustKit.
Al momento è gestito solo a livello Dart (strict TLS).

---

## 5. Build Android (APK / AAB)

### Parametri da avere pronti
Dalla sezione 2 hai:
- `DOMAIN` = tuodominio.com
- `VPS_IP` = IP pubblico del VPS
- `WG_PUBKEY` = la chiave WireGuard pubblica del server (da `server/.env`)
- `CERT_PIN_1` = pin SHA-256 del cert (da sezione 4, opzionale se non ancora attivato)

### Build APK (per distribuzione diretta)
```bash
cd /percorso/Invisible

flutter build apk \
  --obfuscate \
  --split-debug-info=./symbols/android \
  --dart-define=DOMAIN=tuodominio.com \
  --dart-define=VPS_IP=1.2.3.4 \
  --dart-define=WG_PUBKEY=<chiave_wg_pubblica> \
  --dart-define=CERT_PIN_1=<sha256_hex_cert> \
  --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

### Build AAB (per Google Play Store)
```bash
flutter build appbundle \
  --obfuscate \
  --split-debug-info=./symbols/android \
  --dart-define=DOMAIN=tuodominio.com \
  --dart-define=VPS_IP=1.2.3.4 \
  --dart-define=WG_PUBKEY=<chiave_wg_pubblica> \
  --dart-define=CERT_PIN_1=<sha256_hex_cert> \
  --release
```

Output: `build/app/outputs/bundle/release/app-release.aab`

### Cosa fa --obfuscate
- Rinomina tutte le classi/metodi Dart con nomi privi di senso (es. `a.b.c`)
- Rende il reverse engineering dell'APK molto più difficile
- I simboli debug vengono salvati in `./symbols/android/` — tienili al sicuro per deobfuscare i crash

> **IMPORTANTE**: conservare la cartella `symbols/` per ogni versione rilasciata.
> Senza di essa non puoi leggere i crash report.

### Firmare l'APK con chiave di produzione (da fare prima del Play Store)

```bash
# Genera keystore (una volta sola — conserva il file .jks per sempre)
keytool -genkey -v \
  -keystore invisible-release.jks \
  -keyalg RSA -keysize 2048 \
  -validity 10000 \
  -alias invisible

# Aggiungi a android/key.properties:
storePassword=<password>
keyPassword=<password>
keyAlias=invisible
storeFile=../invisible-release.jks
```

Poi in `android/app/build.gradle.kts` sostituire `signingConfigs.getByName("debug")` con la release keystore.

---

## 6. Build iOS (IPA / TestFlight)

### Prerequisiti
- Mac con Xcode ≥ 15
- Apple Developer Account (99 €/anno)
- App registrata su App Store Connect

### Build IPA
```bash
flutter build ipa \
  --obfuscate \
  --split-debug-info=./symbols/ios \
  --dart-define=DOMAIN=tuodominio.com \
  --dart-define=VPS_IP=1.2.3.4 \
  --dart-define=WG_PUBKEY=<chiave_wg_pubblica> \
  --dart-define=CERT_PIN_1=<sha256_hex_cert> \
  --release
```

### Distribuzione via TestFlight (fino a 10.000 tester)
1. Aprire Xcode → Product → Archive
2. In Organizer → Distribute App → TestFlight
3. Su App Store Connect aggiungere i tester via email o link pubblico
4. I tester installano TestFlight da App Store, poi l'app compare automaticamente
5. **Il link TestFlight scade dopo 90 giorni** — rigenerarlo quando scade

### Distribuzione via Apple Developer Enterprise (solo uso interno aziendale)
- Costo: 299 €/anno
- Permette installazione diretta senza App Store su qualsiasi iPhone
- Non adatto per distribuzione pubblica (rischio revoca da parte di Apple)

---

## 7. Distribuzione agli utenti

### Metodo 1: APK diretto (Android)
1. Invia l'APK all'utente (email, messaggio privato, ecc.)
2. L'utente deve abilitare "Installa da fonti sconosciute" nelle impostazioni Android
3. Tap sull'APK → installa

### Metodo 2: TestFlight (iOS — fino a 10.000 utenti)
1. Aggiungi l'email dell'utente su App Store Connect → TestFlight → Tester
2. L'utente riceve un'email con link per installare TestFlight
3. L'invito scade dopo 90 giorni — rinnovare se l'utente non installa in tempo

### Metodo 3: Google Play / App Store (distribuzione pubblica)
- Richiederebbe validazione delle policy (contenuti, privacy policy pubblica, ecc.)
- Non necessario per distribuzione controllata iniziale

---

## 8. Verifica funzionamento

### Dopo il deploy del server
```bash
# Health check di tutti i microservizi
curl https://tuodominio.com/healthz          # nginx → relay
curl https://tuodominio.com/v1/tos/healthz   # legal service

# Verifica connessione WebSocket relay
wscat -c wss://tuodominio.com/v1/relay

# Verifica database PostgreSQL ToS
docker exec -it invisible-postgres \
  psql -U postgres -d invisible \
  -c "SELECT * FROM tos_acceptances LIMIT 10;"
```

### Test completo dall'app
1. Installa l'APK sul telefono
2. Crea un profilo → verifica che la schermata ToS appaia
3. Accetta i ToS → verifica nel DB PostgreSQL che il record sia presente
4. Aggiungi un contatto (QR code) → verifica che la chat funzioni
5. Invia un messaggio → verifica che arrivi cifrato

---

## 9. Aggiornamenti futuri

### Aggiornamento app (nuova versione)
```bash
# Aggiorna il version code in pubspec.yaml:
version: 1.0.1+2  # formato: versionName+versionCode

# Rebuild con gli stessi parametri
flutter build apk --obfuscate ... --release
```

### Rotazione del certificato TLS (ogni 90 giorni con Let's Encrypt)
Let's Encrypt rinnova automaticamente. Se cambi chiave del server:
1. Rigenera il pin SPKI (sezione 4)
2. Aggiorna `network_security_config.xml`
3. Rilascia nuova versione dell'app **prima** che il vecchio cert scada
4. Mantieni sempre 2 pin attivi (principale + backup) per evitare interruzioni

### Aggiornamento ToS (nuova versione)
1. Modifica `lib/utils/constants.dart`: `tosVersion = '2.0'`
2. Aggiorna il testo in `lib/features/onboarding/screens/tos_screen.dart`
3. La chiave SharedPreferences cambierà → ogni utente dovrà riaccettare al login successivo
4. Il microservizio `legal` salverà un nuovo record con `tos_version = '2.0'`

---

## 10. Architettura di sicurezza — riepilogo

### Crittografia messaggi
| Layer | Algoritmo | Dove |
|-------|-----------|------|
| Identity key | Ed25519 | Autenticazione WebSocket, firma ToS |
| Key agreement | X3DH + X25519 | Prima sessione con un contatto |
| Messaggi | Double Ratchet + AES-256-GCM | Ogni messaggio |
| Media | AES-256-GCM separato | File/immagini cifrati prima di inviare |
| Database | SQLCipher + PBKDF2 100k iter | Storage locale |
| Chiavi private | Flutter Secure Storage (KeyStore/Keychain) | Inaccessibili ad altre app |

### Protezione app
| Misura | Stato | Note |
|--------|-------|------|
| ProGuard/R8 obfuscation | ✅ Attivo | `isMinifyEnabled = true` |
| Flutter obfuscation | ✅ Comando build | `--obfuscate --split-debug-info` |
| Root/Jailbreak detection | ✅ Attivo | `safe_device` package, blocca avvio |
| Emulator detection | ✅ Attivo | Blocca avvio su emulatori |
| Developer options detection | ✅ Attivo | Blocca avvio se USB debug attivo |
| Strict TLS (no MITM) | ✅ Attivo | Rifiuta cert non validi in release |
| Android network_security_config | ✅ Attivo | No cleartext, no CA utente |
| allowBackup=false | ✅ Attivo | Backup ADB disabilitato |
| Certificate pinning Android | ⏳ **DA FARE dopo deploy server** | Decommentare blocco `<domain-config>` in `android/app/src/main/res/xml/network_security_config.xml` con pin SPKI SHA-256 (istruzioni in sezione 4) |
| Certificate pinning iOS | ⚠️ **Parziale** | Dart-level strict TLS attivo. Pinning nativo completo richiede TrustKit o NSURLSession in Swift — da implementare in `ios/Runner/AppDelegate.swift` |
| ToS accettazione per profilo | ✅ Attivo | SharedPreferences + PostgreSQL |
| ToS firma Ed25519 | ✅ Attivo | Prova crittografica del consenso |

### Rete
| Componente | Dettaglio |
|-----------|-----------|
| Trasporto | WSS (WebSocket over TLS 1.3) |
| Rete mesh | WireGuard — nasconde IP reale degli utenti |
| Relay | Non vede il contenuto (solo ciphertext E2E) |
| Identità | Solo chiave pubblica Ed25519, nessun numero di telefono |

---

## 11. Comandi utili di manutenzione

### Visualizzare log microservizi
```bash
# Tutti i servizi
docker compose logs -f

# Solo relay
docker compose logs -f relay

# Solo legal (ToS)
docker compose logs -f legal

# Solo nginx
docker compose logs -f nginx
```

### Backup database PostgreSQL
```bash
docker exec invisible-postgres \
  pg_dump -U postgres invisible \
  > backup_tos_$(date +%Y%m%d).sql
```

### Riavvio servizi dopo aggiornamento
```bash
cd server/
git pull
docker compose build
docker compose up -d --force-recreate
```

### Bloccare un utente (revocare accesso)
Attualmente il relay autentica tramite challenge Ed25519. Per bloccare un utente:
1. Aggiungere la sua `identity_key` a una lista di blocco nel relay
2. Aggiornare il microservizio relay con la logica di blacklist

### Verificare quanti utenti hanno accettato i ToS
```bash
docker exec -it invisible-postgres \
  psql -U postgres -d invisible \
  -c "SELECT platform, COUNT(*) FROM tos_acceptances GROUP BY platform;"
```

### Deobfuscare un crash report Android
```bash
# Richiede flutter_tools e il file symbols generato al build
flutter symbolize \
  --input=crash_report.txt \
  --debug-info=symbols/android/app.android-arm64.symbols
```

---

*Documento interno — NON distribuire.*
*Conservare insieme ai file `symbols/` e al keystore `invisible-release.jks`.*

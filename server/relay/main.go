// relay — server WebSocket per consegna messaggi E2E cifrati
// Sealed Sender: il server non vede mai chi ha scritto.
// Riceve solo il destinatario (per instradare) + blob opaco cifrato.
// Il mittente è nascosto dentro la busta, leggibile solo dal destinatario.
// I messaggi sono messi in coda su Redis con TTL automatico (7 giorni).
// Scala orizzontalmente: più pod possono servire utenti diversi contemporaneamente.
package main

import (
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"github.com/redis/go-redis/v9"
)

// ── Configurazione ────────────────────────────────────────────────────────────

var (
	msgTTL = 7 * 24 * time.Hour
	ctx    = context.Background()
)

// ── Tipi messaggi ─────────────────────────────────────────────────────────────

type RelayMsg struct {
	Type          string `json:"type"`
	To            string `json:"to,omitempty"`
	From          string `json:"from,omitempty"`
	Payload       string `json:"payload,omitempty"`        // legacy (non sealed)
	SealedPayload string `json:"sealed_payload,omitempty"` // sealed sender — nessun from
	MsgID         string `json:"msg_id,omitempty"`
	Timestamp     string `json:"timestamp,omitempty"`
	Challenge     string `json:"challenge,omitempty"`
	Signature     string `json:"signature,omitempty"`
	IdentityKey   string `json:"identity_key,omitempty"`
}

// ── Message Store (Redis — persistente, TTL automatico, scala orizzontalmente) ─

type QueuedMsg struct {
	From          string
	To            string
	Payload       string // legacy
	SealedPayload string // sealed sender
	MsgID         string
	Timestamp     time.Time
}

// redisKey costruisce la chiave Redis per un singolo messaggio: "msg:<to>:<msgID>"
func redisKey(to, msgID string) string {
	return fmt.Sprintf("msg:%s:%s", to, msgID)
}

// redisIndexKey costruisce la chiave del set di indice per un destinatario: "idx:<to>"
// Il set contiene tutti i msgID in coda per quell'utente.
func redisIndexKey(to string) string {
	return fmt.Sprintf("idx:%s", to)
}

type MessageStore struct {
	rdb *redis.Client
}

// NewMessageStore crea un client Redis con connessione verificata.
func NewMessageStore(redisAddr string) (*MessageStore, error) {
	rdb := redis.NewClient(&redis.Options{
		Addr:         redisAddr,
		Password:     os.Getenv("REDIS_PASSWORD"), // vuoto se non configurato
		DB:           0,
		DialTimeout:  5 * time.Second,
		ReadTimeout:  3 * time.Second,
		WriteTimeout: 3 * time.Second,
	})
	if err := rdb.Ping(ctx).Err(); err != nil {
		return nil, fmt.Errorf("redis ping: %w", err)
	}
	log.Printf("[RELAY] Redis connesso a %s", redisAddr)
	return &MessageStore{rdb: rdb}, nil
}

// Enqueue salva il messaggio su Redis con TTL automatico.
// Usa una struttura a doppia chiave:
//   - "msg:<to>:<msgID>" → JSON del messaggio (con TTL)
//   - "idx:<to>"         → Set con i msgID in coda (per Drain efficiente)
func (ms *MessageStore) Enqueue(msg QueuedMsg) {
	data, err := json.Marshal(msg)
	if err != nil {
		return
	}
	pipe := ms.rdb.Pipeline()
	msgK := redisKey(msg.To, msg.MsgID)
	idxK := redisIndexKey(msg.To)

	pipe.Set(ctx, msgK, data, msgTTL)
	pipe.SAdd(ctx, idxK, msg.MsgID)
	pipe.Expire(ctx, idxK, msgTTL)
	if _, err := pipe.Exec(ctx); err != nil {
		log.Printf("[RELAY] Enqueue errore: %v", err)
	}
}

// Drain legge e rimuove tutti i messaggi in coda per il recipient.
// Operazione atomica: usa pipeline Redis per minimizzare round-trip.
func (ms *MessageStore) Drain(recipientID string) []QueuedMsg {
	idxK := redisIndexKey(recipientID)

	// Leggi tutti i msgID dell'indice
	msgIDs, err := ms.rdb.SMembers(ctx, idxK).Result()
	if err != nil || len(msgIDs) == 0 {
		return nil
	}

	// Leggi tutti i messaggi in un'unica pipeline
	pipe := ms.rdb.Pipeline()
	cmds := make([]*redis.StringCmd, len(msgIDs))
	for i, id := range msgIDs {
		cmds[i] = pipe.Get(ctx, redisKey(recipientID, id))
	}
	pipe.Del(ctx, idxK)
	pipe.Exec(ctx) //nolint

	var msgs []QueuedMsg
	var toDelete []string
	for i, cmd := range cmds {
		data, err := cmd.Result()
		if err != nil {
			continue
		}
		var m QueuedMsg
		if json.Unmarshal([]byte(data), &m) == nil {
			msgs = append(msgs, m)
			toDelete = append(toDelete, redisKey(recipientID, msgIDs[i]))
		}
	}

	// Rimuovi le chiavi dei messaggi consegnati
	if len(toDelete) > 0 {
		ms.rdb.Del(ctx, toDelete...)
	}

	return msgs
}

// DeleteOne rimuove un singolo messaggio dopo la ricezione dell'ACK.
func (ms *MessageStore) DeleteOne(recipientID, msgID string) {
	pipe := ms.rdb.Pipeline()
	pipe.Del(ctx, redisKey(recipientID, msgID))
	pipe.SRem(ctx, redisIndexKey(recipientID), msgID)
	pipe.Exec(ctx) //nolint
}

// ── Connection ────────────────────────────────────────────────────────────────

type Connection struct {
	id          string
	identityKey string
	conn        *websocket.Conn
	send        chan []byte
	challenge   []byte
	authed      bool
}

func (c *Connection) write(msg RelayMsg) {
	b, err := json.Marshal(msg)
	if err != nil {
		return
	}
	select {
	case c.send <- b:
	default:
	}
}

func (c *Connection) writePump() {
	defer c.conn.Close()
	for b := range c.send {
		if err := c.conn.WriteMessage(websocket.TextMessage, b); err != nil {
			return
		}
	}
}

// ── Registry ──────────────────────────────────────────────────────────────────

type Registry struct {
	mu    sync.RWMutex
	conns map[string]*Connection
}

func NewRegistry() *Registry { return &Registry{conns: make(map[string]*Connection)} }

func (r *Registry) Add(c *Connection) {
	r.mu.Lock()
	r.conns[c.id] = c
	r.mu.Unlock()
}

func (r *Registry) Remove(id string) {
	r.mu.Lock()
	delete(r.conns, id)
	r.mu.Unlock()
}

func (r *Registry) Get(id string) (*Connection, bool) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	c, ok := r.conns[id]
	return c, ok
}

// ── Server ────────────────────────────────────────────────────────────────────

var upgrader = websocket.Upgrader{
	CheckOrigin:     func(*http.Request) bool { return true },
	ReadBufferSize:  32768,
	WriteBufferSize: 32768,
}

type Server struct {
	registry *Registry
	store    *MessageStore
}

func (s *Server) ServeWS(w http.ResponseWriter, r *http.Request) {
	log.Printf("[RELAY] Nuova connessione da %s", r.RemoteAddr)
	wsConn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("[RELAY] Upgrade fallito: %v", err)
		return
	}

	ch := make([]byte, 32)
	rand.Read(ch)

	conn := &Connection{
		conn:      wsConn,
		send:      make(chan []byte, 128),
		challenge: ch,
	}

	go conn.writePump()

	conn.write(RelayMsg{
		Type:      "challenge",
		Challenge: base64.StdEncoding.EncodeToString(ch),
	})

	defer func() {
		if conn.id != "" {
			s.registry.Remove(conn.id)
			s.broadcastPresence(conn, "offline")
			go notifyDisconnect(conn.id)
			log.Printf("[RELAY] Disconnesso: %s", conn.id[:8])
		}
		close(conn.send)
		wsConn.Close()
	}()

	wsConn.SetReadLimit(10 * 1024 * 1024)
	wsConn.SetReadDeadline(time.Now().Add(90 * time.Second))
	wsConn.SetPongHandler(func(string) error {
		wsConn.SetReadDeadline(time.Now().Add(90 * time.Second))
		return nil
	})

	for {
		_, raw, err := wsConn.ReadMessage()
		if err != nil {
			return
		}
		wsConn.SetReadDeadline(time.Now().Add(90 * time.Second))

		var msg RelayMsg
		if err := json.Unmarshal(raw, &msg); err != nil {
			continue
		}

		if !conn.authed {
			if msg.Type == "auth" {
				s.handleAuth(conn, msg)
			}
			continue
		}

		switch msg.Type {
		case "send":
			s.handleSend(conn, msg)
		case "ack":
			s.handleAck(conn, msg)
		case "ping":
			conn.write(RelayMsg{Type: "pong"})
		}
	}
}

func (s *Server) handleAuth(conn *Connection, msg RelayMsg) {
	pubBytes, err := base64.StdEncoding.DecodeString(msg.IdentityKey)
	if err != nil || len(pubBytes) != ed25519.PublicKeySize {
		conn.write(RelayMsg{Type: "auth_fail"})
		return
	}
	sigBytes, err := base64.StdEncoding.DecodeString(msg.Signature)
	if err != nil || !ed25519.Verify(pubBytes, conn.challenge, sigBytes) {
		conn.write(RelayMsg{Type: "auth_fail"})
		return
	}

	idHash := shortHash(msg.IdentityKey)
	log.Printf("[RELAY] Auth attempt hash=%s", idHash[:8])
	if !checkWhitelist(idHash) {
		log.Printf("[RELAY] Auth_fail (not_authorized) hash=%s", idHash[:8])
		conn.write(RelayMsg{Type: "auth_fail", Payload: "not_authorized"})
		return
	}

	conn.identityKey = msg.IdentityKey
	conn.id = idHash
	conn.authed = true

	s.registry.Add(conn)
	conn.write(RelayMsg{Type: "auth_ok", From: conn.id})
	log.Printf("[RELAY] Autenticato: %s", conn.id[:8])
	go notifyPresence(idHash)
	s.broadcastPresence(conn, "online")

	// Consegna messaggi in coda da Redis
	queued := s.store.Drain(conn.id)
	for _, qm := range queued {
		if qm.SealedPayload != "" {
			conn.write(RelayMsg{
				Type:          "deliver",
				SealedPayload: qm.SealedPayload,
				MsgID:         qm.MsgID,
				Timestamp:     qm.Timestamp.UTC().Format(time.RFC3339),
			})
		} else {
			conn.write(RelayMsg{
				Type:      "deliver",
				From:      qm.From,
				Payload:   qm.Payload,
				MsgID:     qm.MsgID,
				Timestamp: qm.Timestamp.UTC().Format(time.RFC3339),
			})
		}
	}
}

func (s *Server) broadcastPresence(src *Connection, status string) {
	s.registry.mu.RLock()
	defer s.registry.mu.RUnlock()
	for id, c := range s.registry.conns {
		if id == src.id {
			continue
		}
		c.write(RelayMsg{
			Type:    "presence",
			From:    src.id,
			Payload: status,
		})
	}
}

func (s *Server) handleSend(from *Connection, msg RelayMsg) {
	if msg.To == "" || msg.MsgID == "" {
		return
	}
	sealed := msg.SealedPayload != ""
	if !sealed && msg.Payload == "" {
		return
	}

	qm := QueuedMsg{
		To:        msg.To,
		MsgID:     msg.MsgID,
		Timestamp: time.Now().UTC(),
	}
	if sealed {
		qm.SealedPayload = msg.SealedPayload
	} else {
		qm.From = from.id
		qm.Payload = msg.Payload
	}

	dest, online := s.registry.Get(msg.To)
	if online {
		// Delay casuale 0–255 ms per impedire correlazioni temporali (traffic analysis)
		go s.deliverWithJitter(dest, qm, sealed, from.id, msg.Payload)
		s.store.Enqueue(qm)
	} else {
		s.store.Enqueue(qm)
	}

	from.write(RelayMsg{Type: "sent_ok", MsgID: msg.MsgID})
}

// deliverWithJitter consegna il messaggio dopo un delay casuale 0–255 ms.
func (s *Server) deliverWithJitter(dest *Connection, qm QueuedMsg, sealed bool, fromID, payload string) {
	var jitter [1]byte
	rand.Read(jitter[:])
	time.Sleep(time.Duration(jitter[0]) * time.Millisecond)

	if sealed {
		dest.write(RelayMsg{
			Type:          "deliver",
			SealedPayload: qm.SealedPayload,
			MsgID:         qm.MsgID,
			Timestamp:     qm.Timestamp.Format(time.RFC3339),
		})
	} else {
		dest.write(RelayMsg{
			Type:      "deliver",
			From:      fromID,
			Payload:   payload,
			MsgID:     qm.MsgID,
			Timestamp: qm.Timestamp.Format(time.RFC3339),
		})
	}
}

// handleAck rimuove il messaggio da Redis dopo conferma di ricezione
func (s *Server) handleAck(conn *Connection, msg RelayMsg) {
	if msg.MsgID != "" {
		s.store.DeleteOne(conn.id, msg.MsgID)
	}
}

// ── Helpers ───────────────────────────────────────────────────────────────────

func shortHash(key string) string {
	if len(key) > 32 {
		return key[len(key)-32:]
	}
	return key
}

func getEnv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func notifyPresence(identityHash string) {
	adminURL := getEnv("ADMIN_URL", "http://invisible-admin:8084")
	http.Post(adminURL+"/internal/presence/"+identityHash, "application/json", nil) //nolint
}

func notifyDisconnect(identityHash string) {
	adminURL := getEnv("ADMIN_URL", "http://invisible-admin:8084")
	req, _ := http.NewRequest(http.MethodDelete, adminURL+"/internal/presence/"+identityHash, nil)
	http.DefaultClient.Do(req) //nolint
}

func checkWhitelist(identityHash string) bool {
	adminURL := getEnv("ADMIN_URL", "http://invisible-admin:8084")
	client := &http.Client{Timeout: 5 * time.Second}
	resp, err := client.Get(adminURL + "/internal/whitelist/" + identityHash)
	if err != nil {
		log.Printf("[RELAY] Whitelist check fallito (admin irraggiungibile): %v", err)
		return false
	}
	defer resp.Body.Close()
	return resp.StatusCode == http.StatusOK
}

// ── Main ──────────────────────────────────────────────────────────────────────

func main() {
	if ttlHours := os.Getenv("MSG_TTL_HOURS"); ttlHours != "" {
		var h int
		if _, err := fmt.Sscanf(ttlHours, "%d", &h); err == nil && h > 0 {
			msgTTL = time.Duration(h) * time.Hour
		}
	}

	port      := getEnv("PORT", "8082")
	redisAddr := getEnv("REDIS_ADDR", "localhost:6379")

	store, err := NewMessageStore(redisAddr)
	if err != nil {
		log.Fatalf("[RELAY] Impossibile connettersi a Redis (%s): %v", redisAddr, err)
	}

	srv := &Server{
		registry: NewRegistry(),
		store:    store,
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/v1/relay", srv.ServeWS)
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		// Health check: verifica anche la connessione Redis
		if err := store.rdb.Ping(ctx).Err(); err != nil {
			w.WriteHeader(http.StatusServiceUnavailable)
			return
		}
		w.WriteHeader(http.StatusOK)
	})

	log.Printf("[RELAY] In ascolto su :%s | Redis: %s | TTL messaggi: %v", port, redisAddr, msgTTL)
	if err := http.ListenAndServe(":"+port, mux); err != nil {
		log.Fatalf("Server error: %v", err)
	}
}

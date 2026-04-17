// relay — server WebSocket per consegna messaggi E2E cifrati
// Il server non può mai leggere il contenuto: vede solo from_id, to_id, payload opaco.
// I messaggi sono messi in coda se il destinatario è offline (TTL 7 giorni).
// Consegna garantita: il mittente riceve ACK solo dopo la conferma del destinatario.
package main

import (
	"bytes"
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
	bolt "go.etcd.io/bbolt"
)

// ── Configurazione ────────────────────────────────────────────────────────────

var msgTTL = 7 * 24 * time.Hour

// ── Tipi messaggi ─────────────────────────────────────────────────────────────

type RelayMsg struct {
	Type      string `json:"type"`
	To        string `json:"to,omitempty"`
	From      string `json:"from,omitempty"`
	Payload   string `json:"payload,omitempty"` // base64 ciphertext opaco
	MsgID     string `json:"msg_id,omitempty"`
	Timestamp string `json:"timestamp,omitempty"`
	Challenge string `json:"challenge,omitempty"`
	Signature string `json:"signature,omitempty"`
	IdentityKey string `json:"identity_key,omitempty"`
}

// ── Message Store (bbolt — persistente su disco) ───────────────────────────────

var bktMessages = []byte("messages")

type QueuedMsg struct {
	From      string
	To        string
	Payload   string
	MsgID     string
	Timestamp time.Time
}

// msgKey costruisce la chiave bbolt: "<recipientID>:<msgID>"
// Il prefisso recipientID permette Seek efficiente per Drain.
func msgKey(to, msgID string) []byte {
	return []byte(to + ":" + msgID)
}

type MessageStore struct {
	db *bolt.DB
}

// NewMessageStore apre (o crea) il database bbolt al path indicato.
func NewMessageStore(path string) (*MessageStore, error) {
	db, err := bolt.Open(path, 0600, &bolt.Options{Timeout: 5 * time.Second})
	if err != nil {
		return nil, fmt.Errorf("bbolt open: %w", err)
	}
	if err := db.Update(func(tx *bolt.Tx) error {
		_, err := tx.CreateBucketIfNotExists(bktMessages)
		return err
	}); err != nil {
		return nil, err
	}
	ms := &MessageStore{db: db}
	go ms.cleanup()
	return ms, nil
}

func (ms *MessageStore) Enqueue(msg QueuedMsg) {
	data, err := json.Marshal(msg)
	if err != nil {
		return
	}
	_ = ms.db.Update(func(tx *bolt.Tx) error {
		return tx.Bucket(bktMessages).Put(msgKey(msg.To, msg.MsgID), data)
	})
}

// Drain legge e rimuove tutti i messaggi in coda per il recipient.
func (ms *MessageStore) Drain(recipientID string) []QueuedMsg {
	prefix := []byte(recipientID + ":")
	var msgs []QueuedMsg
	var keys [][]byte

	_ = ms.db.View(func(tx *bolt.Tx) error {
		c := tx.Bucket(bktMessages).Cursor()
		for k, v := c.Seek(prefix); k != nil && bytes.HasPrefix(k, prefix); k, v = c.Next() {
			var m QueuedMsg
			if json.Unmarshal(v, &m) == nil {
				msgs = append(msgs, m)
				keys = append(keys, append([]byte{}, k...))
			}
		}
		return nil
	})

	if len(keys) > 0 {
		_ = ms.db.Update(func(tx *bolt.Tx) error {
			b := tx.Bucket(bktMessages)
			for _, k := range keys {
				_ = b.Delete(k)
			}
			return nil
		})
	}
	return msgs
}

func (ms *MessageStore) DeleteOne(recipientID, msgID string) {
	_ = ms.db.Update(func(tx *bolt.Tx) error {
		return tx.Bucket(bktMessages).Delete(msgKey(recipientID, msgID))
	})
}

// cleanup rimuove ogni ora i messaggi scaduti (TTL superato).
func (ms *MessageStore) cleanup() {
	for range time.Tick(time.Hour) {
		_ = ms.db.Update(func(tx *bolt.Tx) error {
			b := tx.Bucket(bktMessages)
			c := b.Cursor()
			var expired [][]byte
			for k, v := c.First(); k != nil; k, v = c.Next() {
				var m QueuedMsg
				if json.Unmarshal(v, &m) != nil || time.Since(m.Timestamp) > msgTTL {
					expired = append(expired, append([]byte{}, k...))
				}
			}
			for _, k := range expired {
				_ = b.Delete(k)
			}
			return nil
		})
	}
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

	// Manda challenge al client
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

	wsConn.SetReadLimit(10 * 1024 * 1024) // max 10 MB per messaggio (supporta immagini/file cifrati)
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

	// Verifica whitelist admin
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

	// Notifica gli altri utenti connessi che questo è ora online
	s.broadcastPresence(conn, "online")

	// Consegna messaggi in coda
	queued := s.store.Drain(conn.id)
	for _, qm := range queued {
		conn.write(RelayMsg{
			Type:      "deliver",
			From:      qm.From,
			Payload:   qm.Payload,
			MsgID:     qm.MsgID,
			Timestamp: qm.Timestamp.UTC().Format(time.RFC3339),
		})
	}
}

// broadcastPresence invia un evento presenza a tutti gli altri utenti connessi.
func (s *Server) broadcastPresence(src *Connection, status string) {
	s.registry.mu.RLock()
	defer s.registry.mu.RUnlock()
	for id, c := range s.registry.conns {
		if id == src.id {
			continue // non mandare a se stesso
		}
		c.write(RelayMsg{
			Type:   "presence",
			From:   src.id,
			Payload: status, // "online" | "offline"
		})
	}
}

func (s *Server) handleSend(from *Connection, msg RelayMsg) {
	if msg.To == "" || msg.Payload == "" || msg.MsgID == "" {
		return
	}

	qm := QueuedMsg{
		From:      from.id,
		To:        msg.To,
		Payload:   msg.Payload,
		MsgID:     msg.MsgID,
		Timestamp: time.Now().UTC(),
	}

	dest, online := s.registry.Get(msg.To)
	if online {
		// Consegna immediata
		dest.write(RelayMsg{
			Type:      "deliver",
			From:      from.id,
			Payload:   msg.Payload,
			MsgID:     msg.MsgID,
			Timestamp: qm.Timestamp.Format(time.RFC3339),
		})
		// Metti in coda temporaneamente fino all'ACK
		s.store.Enqueue(qm)
	} else {
		// Destinatario offline — metti in coda per 7 giorni
		s.store.Enqueue(qm)
	}

	// Conferma ricezione al mittente
	from.write(RelayMsg{Type: "sent_ok", MsgID: msg.MsgID})
}

// handleAck: il destinatario ha ricevuto e decriptato — rimuoviamo dalla coda
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
		return false // nega per default — sicurezza prima di tutto
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

	port    := getEnv("PORT", "8082")
	dbPath  := getEnv("MSG_DB_PATH", "/data/relay.db")

	store, err := NewMessageStore(dbPath)
	if err != nil {
		log.Fatalf("Impossibile aprire message store (%s): %v", dbPath, err)
	}

	srv := &Server{
		registry: NewRegistry(),
		store:    store,
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/v1/relay", srv.ServeWS)
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})

	log.Printf("[RELAY] In ascolto su :%s | TTL messaggi: %v", port, msgTTL)
	if err := http.ListenAndServe(":"+port, mux); err != nil {
		log.Fatalf("Server error: %v", err)
	}
}


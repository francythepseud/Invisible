// signaling — server WebSocket per segnalazione WebRTC
// Autentica gli utenti via Ed25519 challenge-response.
// Instrada SDP offer/answer e ICE candidates tra peer.
// NON vede mai il contenuto delle chiamate (E2E DTLS-SRTP).
package main

import (
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

// ── Tipi messaggi ─────────────────────────────────────────────────────────────

const (
	MsgGetChallenge = "get_challenge"
	MsgAuth         = "auth"
	MsgAuthOK       = "auth_ok"
	MsgAuthFail     = "auth_fail"
	MsgOffer        = "offer"
	MsgAnswer       = "answer"
	MsgIce          = "ice"
	MsgHangup       = "hangup"
	MsgPing         = "ping"
	MsgPong         = "pong"
	MsgError        = "error"
)

type Message struct {
	Type      string          `json:"type"`
	To        string          `json:"to,omitempty"`
	From      string          `json:"from,omitempty"`
	Payload   json.RawMessage `json:"payload,omitempty"`
	Challenge string          `json:"challenge,omitempty"`
	Signature string          `json:"signature,omitempty"`
	IdentityKey string        `json:"identity_key,omitempty"`
}

// ── Connection ────────────────────────────────────────────────────────────────

type Connection struct {
	id          string // hash dell'identity key
	identityKey string // Ed25519 public key base64
	conn        *websocket.Conn
	send        chan []byte
	authed      bool
	challenge   []byte
	createdAt   time.Time
}

func (c *Connection) write(msg Message) error {
	b, err := json.Marshal(msg)
	if err != nil {
		return err
	}
	select {
	case c.send <- b:
	default:
		return nil // buffer pieno — drop
	}
	return nil
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
	conns map[string]*Connection // id → Connection
}

func NewRegistry() *Registry {
	return &Registry{conns: make(map[string]*Connection)}
}

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
	CheckOrigin:     func(r *http.Request) bool { return true },
	ReadBufferSize:  4096,
	WriteBufferSize: 4096,
}

type Server struct {
	registry *Registry
}

func (s *Server) ServeWS(w http.ResponseWriter, r *http.Request) {
	wsConn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		return
	}

	// Genera challenge iniziale
	ch := make([]byte, 32)
	rand.Read(ch)

	conn := &Connection{
		conn:      wsConn,
		send:      make(chan []byte, 64),
		challenge: ch,
		createdAt: time.Now(),
	}

	go conn.writePump()

	// Invia challenge immediatamente
	conn.write(Message{
		Type:      "challenge",
		Challenge: base64.StdEncoding.EncodeToString(ch),
	})

	defer func() {
		if conn.id != "" {
			s.registry.Remove(conn.id)
			log.Printf("[SIGNAL] Disconnesso: %s", conn.id[:8])
		}
		close(conn.send)
		wsConn.Close()
	}()

	wsConn.SetReadLimit(64 * 1024)
	wsConn.SetReadDeadline(time.Now().Add(60 * time.Second))
	wsConn.SetPongHandler(func(string) error {
		wsConn.SetReadDeadline(time.Now().Add(60 * time.Second))
		return nil
	})

	for {
		_, raw, err := wsConn.ReadMessage()
		if err != nil {
			return
		}
		wsConn.SetReadDeadline(time.Now().Add(60 * time.Second))

		var msg Message
		if err := json.Unmarshal(raw, &msg); err != nil {
			continue
		}

		if !conn.authed {
			if msg.Type == MsgAuth {
				s.handleAuth(conn, msg)
			}
			continue
		}

		switch msg.Type {
		case MsgOffer, MsgAnswer, MsgIce, MsgHangup:
			s.route(conn, msg)
		case MsgPing:
			conn.write(Message{Type: MsgPong})
		}
	}
}

func (s *Server) handleAuth(conn *Connection, msg Message) {
	pubKeyBytes, err := base64.StdEncoding.DecodeString(msg.IdentityKey)
	if err != nil || len(pubKeyBytes) != ed25519.PublicKeySize {
		conn.write(Message{Type: MsgAuthFail})
		return
	}
	sigBytes, err := base64.StdEncoding.DecodeString(msg.Signature)
	if err != nil {
		conn.write(Message{Type: MsgAuthFail})
		return
	}
	if !ed25519.Verify(pubKeyBytes, conn.challenge, sigBytes) {
		conn.write(Message{Type: MsgAuthFail})
		return
	}

	idHash := shortHash(msg.IdentityKey)
	if !checkWhitelist(idHash) {
		conn.write(Message{Type: MsgAuthFail})
		return
	}

	conn.identityKey = msg.IdentityKey
	conn.id = idHash
	conn.authed = true

	s.registry.Add(conn)
	conn.write(Message{Type: MsgAuthOK, From: conn.id})
	log.Printf("[SIGNAL] Autenticato: %s", conn.id[:8])
}

// route instrada un messaggio al destinatario identificato da To (id hash)
func (s *Server) route(from *Connection, msg Message) {
	if msg.To == "" {
		return
	}
	dest, ok := s.registry.Get(msg.To)
	if !ok {
		from.write(Message{Type: MsgError, Payload: jsonStr("peer offline")})
		return
	}
	dest.write(Message{
		Type:    msg.Type,
		From:    from.id,
		Payload: msg.Payload,
	})
}

// ── Helpers ───────────────────────────────────────────────────────────────────

func shortHash(key string) string {
	// Identificatore pubblico: ultimi 32 char base64 della chiave
	if len(key) > 32 {
		return key[len(key)-32:]
	}
	return key
}

func jsonStr(s string) json.RawMessage {
	b, _ := json.Marshal(s)
	return b
}

// ── Main ──────────────────────────────────────────────────────────────────────

func main() {
	port := getEnv("PORT", "8081")
	srv := &Server{registry: NewRegistry()}

	mux := http.NewServeMux()
	mux.HandleFunc("/v1/signal", srv.ServeWS)
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})

	log.Printf("[SIGNALING] In ascolto su :%s", port)
	if err := http.ListenAndServe(":"+port, mux); err != nil {
		log.Fatalf("Server error: %v", err)
	}
}

func getEnv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func checkWhitelist(identityHash string) bool {
	adminURL := getEnv("ADMIN_URL", "http://invisible-admin:8084")
	resp, err := http.Get(adminURL + "/internal/whitelist/" + identityHash)
	if err != nil {
		log.Printf("[SIGNAL] Whitelist check fallito (admin irraggiungibile): %v", err)
		return true
	}
	defer resp.Body.Close()
	return resp.StatusCode == http.StatusOK
}

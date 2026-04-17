// legal — microservizio per registrazione accettazione ToS
// Salva su PostgreSQL: hash chiave pubblica, versione ToS, timestamp, IP, piattaforma.
// La firma Ed25519 prova che l'utente ha accettato intenzionalmente.
package main

import (
	"crypto/ed25519"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	_ "github.com/lib/pq"
)

// ── Tipi ──────────────────────────────────────────────────────────────────────

type AcceptRequest struct {
	IdentityKey string `json:"identity_key"` // Ed25519 pubkey base64
	TosVersion  string `json:"tos_version"`  // es. "1.0"
	AppVersion  string `json:"app_version"`  // es. "1.0.0"
	Platform    string `json:"platform"`     // "android" | "ios"
	Signature   string `json:"signature"`    // Ed25519 sign di tosPayload()
}

type CheckResponse struct {
	Accepted   bool   `json:"accepted"`
	TosVersion string `json:"tos_version,omitempty"`
	AcceptedAt string `json:"accepted_at,omitempty"`
}

// tosPayload è il messaggio esatto che il client firma — immutabile per ogni versione ToS.
func tosPayload(version string) []byte {
	return []byte(fmt.Sprintf("invisible_tos_v%s_accepted", version))
}

// identityHash restituisce SHA-256 hex della chiave pubblica.
// Non è reversibile — non espone l'identità ma garantisce unicità.
func identityHash(identityKey string) string {
	h := sha256.Sum256([]byte(identityKey))
	return hex.EncodeToString(h[:])
}

// ── Database ──────────────────────────────────────────────────────────────────

type DB struct {
	db *sql.DB
}

func NewDB(dsn string) (*DB, error) {
	db, err := sql.Open("postgres", dsn)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(10)
	db.SetMaxIdleConns(5)
	db.SetConnMaxLifetime(5 * time.Minute)

	if err := db.Ping(); err != nil {
		return nil, fmt.Errorf("postgres ping: %w", err)
	}

	if _, err := db.Exec(`
		CREATE TABLE IF NOT EXISTS tos_acceptances (
			id              SERIAL PRIMARY KEY,
			identity_hash   TEXT        NOT NULL,
			identity_key    TEXT        NOT NULL,
			tos_version     TEXT        NOT NULL,
			app_version     TEXT        NOT NULL,
			platform        TEXT        NOT NULL,
			ip_address      TEXT        NOT NULL,
			accepted_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			UNIQUE(identity_hash, tos_version)
		);
		CREATE INDEX IF NOT EXISTS idx_tos_identity ON tos_acceptances(identity_hash);
	`); err != nil {
		return nil, fmt.Errorf("migrate: %w", err)
	}

	return &DB{db: db}, nil
}

func (d *DB) Save(idHash, idKey, tosVersion, appVersion, platform, ip string) error {
	_, err := d.db.Exec(`
		INSERT INTO tos_acceptances (identity_hash, identity_key, tos_version, app_version, platform, ip_address)
		VALUES ($1, $2, $3, $4, $5, $6)
		ON CONFLICT (identity_hash, tos_version) DO UPDATE
		  SET accepted_at = NOW(), ip_address = $6, app_version = $4
	`, idHash, idKey, tosVersion, appVersion, platform, ip)
	return err
}

func (d *DB) Check(idHash, tosVersion string) (bool, time.Time, error) {
	var acceptedAt time.Time
	err := d.db.QueryRow(`
		SELECT accepted_at FROM tos_acceptances
		WHERE identity_hash = $1 AND tos_version = $2
	`, idHash, tosVersion).Scan(&acceptedAt)
	if err == sql.ErrNoRows {
		return false, time.Time{}, nil
	}
	if err != nil {
		return false, time.Time{}, err
	}
	return true, acceptedAt, nil
}

// ── Handlers ──────────────────────────────────────────────────────────────────

type Server struct {
	db *DB
}

func (s *Server) handleAccept(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req AcceptRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid json", http.StatusBadRequest)
		return
	}

	// Validazione campi
	if req.IdentityKey == "" || req.TosVersion == "" || req.Signature == "" {
		http.Error(w, "missing fields", http.StatusBadRequest)
		return
	}

	// Decodifica chiave pubblica
	pubBytes, err := base64.StdEncoding.DecodeString(req.IdentityKey)
	if err != nil || len(pubBytes) != ed25519.PublicKeySize {
		http.Error(w, "invalid identity key", http.StatusBadRequest)
		return
	}

	// Verifica firma — prova che l'utente possiede la chiave privata
	sigBytes, err := base64.StdEncoding.DecodeString(req.Signature)
	if err != nil || !ed25519.Verify(pubBytes, tosPayload(req.TosVersion), sigBytes) {
		http.Error(w, "invalid signature", http.StatusUnauthorized)
		return
	}

	// IP reale (dietro nginx)
	ip := r.Header.Get("X-Real-IP")
	if ip == "" {
		ip = r.RemoteAddr
	}

	if len(req.Platform) > 20 {
		req.Platform = req.Platform[:20]
	}
	if len(req.AppVersion) > 20 {
		req.AppVersion = req.AppVersion[:20]
	}
	if len(req.TosVersion) > 10 {
		req.TosVersion = req.TosVersion[:10]
	}

	idHash := identityHash(req.IdentityKey)
	if err := s.db.Save(idHash, req.IdentityKey, req.TosVersion, req.AppVersion, req.Platform, ip); err != nil {
		log.Printf("[LEGAL] Errore salvataggio: %v", err)
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}

	log.Printf("[LEGAL] ToS v%s accettata da %s... via %s (%s)", req.TosVersion, idHash[:8], ip, req.Platform)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "accepted"})
}

func (s *Server) handleCheck(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	idKey := r.URL.Query().Get("identity_key")
	tosVersion := r.URL.Query().Get("tos_version")
	if idKey == "" || tosVersion == "" {
		http.Error(w, "missing params", http.StatusBadRequest)
		return
	}

	idHash := identityHash(idKey)
	accepted, acceptedAt, err := s.db.Check(idHash, tosVersion)
	if err != nil {
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}

	resp := CheckResponse{Accepted: accepted}
	if accepted {
		resp.TosVersion = tosVersion
		resp.AcceptedAt = acceptedAt.UTC().Format(time.RFC3339)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

// ── Main ──────────────────────────────────────────────────────────────────────

func main() {
	dsn := os.Getenv("POSTGRES_DSN")
	if dsn == "" {
		host := getEnv("POSTGRES_HOST", "postgres")
		port := getEnv("POSTGRES_PORT", "5432")
		user := getEnv("POSTGRES_USER", "invisible")
		pass := os.Getenv("POSTGRES_PASSWORD")
		dbname := getEnv("POSTGRES_DB", "invisible")
		dsn = fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=disable",
			host, port, user, pass, dbname)
	}

	db, err := NewDB(dsn)
	if err != nil {
		log.Fatalf("[LEGAL] Connessione PostgreSQL fallita: %v", err)
	}
	log.Println("[LEGAL] Connesso a PostgreSQL")

	srv := &Server{db: db}
	port := getEnv("PORT", "8083")

	mux := http.NewServeMux()
	mux.HandleFunc("/v1/tos/accept", srv.handleAccept)
	mux.HandleFunc("/v1/tos/check", srv.handleCheck)
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})

	log.Printf("[LEGAL] In ascolto su :%s", port)
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

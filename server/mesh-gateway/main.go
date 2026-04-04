// mesh-gateway — gestisce autenticazione Ed25519 e peer WireGuard
// Ogni utente si autentica con la propria identity key (senza username/password),
// ottiene un IP nella rete mesh (10.7.0.0/16) e una config WireGuard pronta.
package main

import (
	"crypto/ed25519"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"sync"
	"time"
)

// ── Configurazione ────────────────────────────────────────────────────────────

type Config struct {
	Port           string // HTTP API port
	WgInterface    string // es. wg0
	WgPort         int    // UDP port WireGuard
	MeshNetwork    string // es. 10.7.0.0/16
	ServerEndpoint string // es. vps.example.com:51820
	ServerWgPriv   string // WireGuard private key del server (base64)
	ServerWgPub    string // WireGuard public key del server (base64)
}

func loadConfig() Config {
	return Config{
		Port:           getEnv("MESH_PORT", "8080"),
		WgInterface:    getEnv("WG_INTERFACE", "wg0"),
		WgPort:         51820,
		MeshNetwork:    getEnv("WG_NETWORK", "10.7.0.0/16"),
		ServerEndpoint: getEnv("SERVER_ENDPOINT", "127.0.0.1:51820"),
		ServerWgPriv:   getEnv("SERVER_WG_PRIV", ""),
		ServerWgPub:    getEnv("SERVER_WG_PUB", ""),
	}
}

func getEnv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

// ── IP Pool ───────────────────────────────────────────────────────────────────

// IPPool assegna IP dalla rete mesh evitando collisioni.
type IPPool struct {
	mu       sync.Mutex
	network  *net.IPNet
	assigned map[string]net.IP // identityKeyHash → IP
	reverse  map[string]string // IP.String() → identityKeyHash
	next     net.IP
}

func NewIPPool(cidr string) (*IPPool, error) {
	_, network, err := net.ParseCIDR(cidr)
	if err != nil {
		return nil, err
	}
	// Prima IP disponibile: network + 2 (es. 10.7.0.2, saltiamo .1 = server)
	start := cloneIP(network.IP)
	inc(start)
	inc(start) // 10.7.0.2
	return &IPPool{
		network:  network,
		assigned: make(map[string]net.IP),
		reverse:  make(map[string]string),
		next:     start,
	}, nil
}

func (p *IPPool) Assign(idHash string) (net.IP, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if ip, ok := p.assigned[idHash]; ok {
		return ip, nil
	}
	for p.network.Contains(p.next) {
		ip := cloneIP(p.next)
		inc(p.next)
		if _, used := p.reverse[ip.String()]; !used {
			p.assigned[idHash] = ip
			p.reverse[ip.String()] = idHash
			return ip, nil
		}
	}
	return nil, fmt.Errorf("pool IP esaurito")
}

func (p *IPPool) Release(idHash string) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if ip, ok := p.assigned[idHash]; ok {
		delete(p.reverse, ip.String())
		delete(p.assigned, idHash)
	}
}

func cloneIP(ip net.IP) net.IP {
	c := make(net.IP, len(ip))
	copy(c, ip)
	return c
}

func inc(ip net.IP) {
	for i := len(ip) - 1; i >= 0; i-- {
		ip[i]++
		if ip[i] != 0 {
			break
		}
	}
}

// ── Challenge Store ───────────────────────────────────────────────────────────

type challenge struct {
	value     []byte
	createdAt time.Time
}

type ChallengeStore struct {
	mu     sync.Mutex
	store  map[string]challenge // identityKey → challenge
	ttl    time.Duration
}

func NewChallengeStore() *ChallengeStore {
	cs := &ChallengeStore{
		store: make(map[string]challenge),
		ttl:   2 * time.Minute,
	}
	go cs.cleanup()
	return cs
}

func (cs *ChallengeStore) New(identityKey string) ([]byte, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return nil, err
	}
	cs.mu.Lock()
	cs.store[identityKey] = challenge{value: b, createdAt: time.Now()}
	cs.mu.Unlock()
	return b, nil
}

func (cs *ChallengeStore) Consume(identityKey string) ([]byte, bool) {
	cs.mu.Lock()
	defer cs.mu.Unlock()
	c, ok := cs.store[identityKey]
	if !ok || time.Since(c.createdAt) > cs.ttl {
		delete(cs.store, identityKey)
		return nil, false
	}
	delete(cs.store, identityKey) // one-shot
	return c.value, true
}

func (cs *ChallengeStore) cleanup() {
	for range time.Tick(30 * time.Second) {
		cs.mu.Lock()
		for k, v := range cs.store {
			if time.Since(v.createdAt) > cs.ttl {
				delete(cs.store, k)
			}
		}
		cs.mu.Unlock()
	}
}

// ── Peer Registry ─────────────────────────────────────────────────────────────

type Peer struct {
	IdentityKey string
	WgPublicKey string
	AssignedIP  string
	ConnectedAt time.Time
}

type PeerRegistry struct {
	mu    sync.RWMutex
	peers map[string]*Peer // identityKeyHash → Peer
}

func NewPeerRegistry() *PeerRegistry {
	return &PeerRegistry{peers: make(map[string]*Peer)}
}

func (r *PeerRegistry) Add(p *Peer) {
	hash := hashKey(p.IdentityKey)
	r.mu.Lock()
	r.peers[hash] = p
	r.mu.Unlock()
}

func (r *PeerRegistry) Remove(identityKey string) {
	r.mu.Lock()
	delete(r.peers, hashKey(identityKey))
	r.mu.Unlock()
}

func (r *PeerRegistry) List() []*Peer {
	r.mu.RLock()
	defer r.mu.RUnlock()
	out := make([]*Peer, 0, len(r.peers))
	for _, p := range r.peers {
		out = append(out, p)
	}
	return out
}

// ── WireGuard Manager ─────────────────────────────────────────────────────────

// WgManager gestisce i peer WireGuard tramite wg CLI.
// In produzione su Linux usa wgctrl; qui usiamo exec per portabilità.
type WgManager struct {
	iface string
}

func NewWgManager(iface string) *WgManager {
	return &WgManager{iface: iface}
}

func (w *WgManager) AddPeer(wgPubKey, allowedIP string) error {
	// wg set wg0 peer <pubkey> allowed-ips <ip>/32
	return runWg("set", w.iface, "peer", wgPubKey, "allowed-ips", allowedIP+"/32")
}

func (w *WgManager) RemovePeer(wgPubKey string) error {
	return runWg("set", w.iface, "peer", wgPubKey, "remove")
}

func runWg(args ...string) error {
	out, err := exec.Command("wg", args...).CombinedOutput()
	if err != nil {
		return fmt.Errorf("wg %v: %w — %s", args, err, out)
	}
	log.Printf("[WG] wg %v → ok", args)
	return nil
}

// ── Server ────────────────────────────────────────────────────────────────────

type Server struct {
	cfg        Config
	challenges *ChallengeStore
	ipPool     *IPPool
	peers      *PeerRegistry
	wg         *WgManager
}

func NewServer(cfg Config) (*Server, error) {
	pool, err := NewIPPool(cfg.MeshNetwork)
	if err != nil {
		return nil, err
	}
	return &Server{
		cfg:        cfg,
		challenges: NewChallengeStore(),
		ipPool:     pool,
		peers:      NewPeerRegistry(),
		wg:         NewWgManager(cfg.WgInterface),
	}, nil
}

// POST /v1/mesh/challenge  { "identity_key": "base64_ed25519_pubkey" }
func (s *Server) handleChallenge(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var req struct {
		IdentityKey string `json:"identity_key"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.IdentityKey == "" {
		http.Error(w, "bad request", http.StatusBadRequest)
		return
	}
	// Valida che sia una chiave Ed25519 valida (32 byte)
	keyBytes, err := base64.StdEncoding.DecodeString(req.IdentityKey)
	if err != nil || len(keyBytes) != ed25519.PublicKeySize {
		http.Error(w, "invalid identity key", http.StatusBadRequest)
		return
	}
	ch, err := s.challenges.New(req.IdentityKey)
	if err != nil {
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}
	jsonResp(w, map[string]string{
		"challenge": base64.StdEncoding.EncodeToString(ch),
	})
}

// POST /v1/mesh/connect
// { "identity_key":..., "wg_pubkey":..., "challenge":..., "signature":... }
func (s *Server) handleConnect(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var req struct {
		IdentityKey string `json:"identity_key"`
		WgPublicKey string `json:"wg_pubkey"`
		Challenge   string `json:"challenge"`
		Signature   string `json:"signature"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "bad request", http.StatusBadRequest)
		return
	}

	// Verifica challenge
	expectedChallenge, ok := s.challenges.Consume(req.IdentityKey)
	if !ok {
		http.Error(w, "challenge scaduto o non trovato", http.StatusUnauthorized)
		return
	}
	challengeBytes, err := base64.StdEncoding.DecodeString(req.Challenge)
	if err != nil || string(challengeBytes) != string(expectedChallenge) {
		http.Error(w, "challenge non corrispondente", http.StatusUnauthorized)
		return
	}

	// Verifica firma Ed25519
	pubKeyBytes, err := base64.StdEncoding.DecodeString(req.IdentityKey)
	if err != nil {
		http.Error(w, "invalid identity key", http.StatusBadRequest)
		return
	}
	sigBytes, err := base64.StdEncoding.DecodeString(req.Signature)
	if err != nil || !ed25519.Verify(pubKeyBytes, expectedChallenge, sigBytes) {
		http.Error(w, "firma non valida", http.StatusUnauthorized)
		return
	}

	// Verifica whitelist admin (stesso formato shortHash del relay)
	if !checkWhitelist(shortHash(req.IdentityKey)) {
		http.Error(w, "not_authorized", http.StatusForbidden)
		return
	}

	// Assegna IP mesh
	ip, err := s.ipPool.Assign(hashKey(req.IdentityKey))
	if err != nil {
		http.Error(w, "pool IP esaurito", http.StatusServiceUnavailable)
		return
	}

	// Aggiungi peer WireGuard
	if err := s.wg.AddPeer(req.WgPublicKey, ip.String()); err != nil {
		http.Error(w, "errore aggiunta peer WireGuard", http.StatusInternalServerError)
		return
	}

	s.peers.Add(&Peer{
		IdentityKey: req.IdentityKey,
		WgPublicKey: req.WgPublicKey,
		AssignedIP:  ip.String(),
		ConnectedAt: time.Now(),
	})

	log.Printf("[MESH] Connesso: %s → %s", hashKey(req.IdentityKey)[:8], ip)

	jsonResp(w, map[string]string{
		"assigned_ip":    ip.String(),
		"server_wg_pub":  s.cfg.ServerWgPub,
		"server_endpoint": s.cfg.ServerEndpoint,
		"mesh_network":   s.cfg.MeshNetwork,
	})
}

// DELETE /v1/mesh/disconnect  — header Authorization: <identity_key>
func (s *Server) handleDisconnect(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodDelete {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	identityKey := r.Header.Get("X-Identity-Key")
	if identityKey == "" {
		http.Error(w, "missing identity key", http.StatusBadRequest)
		return
	}
	// Trova il peer e rimuovi
	for _, p := range s.peers.List() {
		if p.IdentityKey == identityKey {
			s.wg.RemovePeer(p.WgPublicKey)
			s.ipPool.Release(hashKey(identityKey))
			s.peers.Remove(identityKey)
			break
		}
	}
	jsonResp(w, map[string]bool{"ok": true})
}

// GET /v1/mesh/peers  — lista IP dei peer connessi (per routing interno)
func (s *Server) handlePeers(w http.ResponseWriter, r *http.Request) {
	type peerInfo struct {
		ID string `json:"id"`
		IP string `json:"ip"`
	}
	peers := s.peers.List()
	out := make([]peerInfo, 0, len(peers))
	for _, p := range peers {
		out = append(out, peerInfo{
			ID: hashKey(p.IdentityKey)[:16],
			IP: p.AssignedIP,
		})
	}
	jsonResp(w, out)
}

// ── Helpers ───────────────────────────────────────────────────────────────────

func checkWhitelist(identityHash string) bool {
	adminURL := getEnv("ADMIN_URL", "http://invisible-admin:8084")
	resp, err := http.Get(adminURL + "/internal/whitelist/" + identityHash)
	if err != nil {
		log.Printf("[MESH] Whitelist check fallito (admin irraggiungibile): %v", err)
		return true
	}
	defer resp.Body.Close()
	return resp.StatusCode == http.StatusOK
}

func hashKey(key string) string {
	h := sha256.Sum256([]byte(key))
	return hex.EncodeToString(h[:])
}

// shortHash restituisce gli ultimi 32 caratteri della chiave base64,
// stesso formato usato dal relay e dalla whitelist admin.
func shortHash(key string) string {
	if len(key) > 32 {
		return key[len(key)-32:]
	}
	return key
}

func jsonResp(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(v)
}

// ── Main ──────────────────────────────────────────────────────────────────────

func main() {
	cfg := loadConfig()

	srv, err := NewServer(cfg)
	if err != nil {
		log.Fatalf("Errore inizializzazione: %v", err)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/v1/mesh/challenge", srv.handleChallenge)
	mux.HandleFunc("/v1/mesh/connect", srv.handleConnect)
	mux.HandleFunc("/v1/mesh/disconnect", srv.handleDisconnect)
	mux.HandleFunc("/v1/mesh/peers", srv.handlePeers)
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})

	addr := ":" + cfg.Port
	log.Printf("[MESH-GATEWAY] In ascolto su %s | WireGuard: %s | Rete: %s",
		addr, cfg.WgInterface, cfg.MeshNetwork)

	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatalf("Server error: %v", err)
	}
}

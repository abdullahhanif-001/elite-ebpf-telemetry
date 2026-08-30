package elitecontroller

import (
	"io"
	"log"
	"net/http"
	"regexp"
	"strconv"
	"sync"
	"time"
)

// Config drives federation polling.
type Config struct {
	NodeURLs   []string
	Interval   time.Duration
	RhoCap     float64
	PolicyPath string
}

// FederatedPolicy is the aggregated overload view.
type FederatedPolicy struct {
	PolicyVersion uint64  `json:"policy_version"`
	MaxRho        float64 `json:"max_rho"`
	MaxOverload   float64 `json:"max_overload"`
	NodeCount     int     `json:"node_count"`
	UpdatedAt     string  `json:"updated_at"`
}

// Federator polls elite_predict_* from multiple agents.
type Federator struct {
	cfg  Config
	mu   sync.RWMutex
	snap FederatedPolicy
}

// NewFederator builds a federator.
func NewFederator(cfg Config) *Federator {
	if cfg.Interval <= 0 {
		cfg.Interval = 5 * time.Second
	}
	if cfg.RhoCap <= 0 {
		cfg.RhoCap = 0.85
	}
	return &Federator{cfg: cfg}
}

// Run polls until process exit (caller typically runs in goroutine).
func (f *Federator) Run() {
	t := time.NewTicker(f.cfg.Interval)
	defer t.Stop()
	ver := uint64(1)
	for range t.C {
		maxRho := 0.0
		maxO := 0.0
		n := 0
		for _, u := range f.cfg.NodeURLs {
			rho, overload, ok := scrapeNode(u)
			if !ok {
				continue
			}
			n++
			if rho > maxRho {
				maxRho = rho
			}
			if overload > maxO {
				maxO = overload
			}
		}
		ver++
		f.mu.Lock()
		f.snap = FederatedPolicy{
			PolicyVersion: ver,
			MaxRho:        maxRho,
			MaxOverload:   maxO,
			NodeCount:     n,
			UpdatedAt:     time.Now().Format(time.RFC3339),
		}
		f.mu.Unlock()
		if maxRho > f.cfg.RhoCap {
			log.Printf("elite-controller: max_rho=%.3f overload=%.3f nodes=%d", maxRho, maxO, n)
		}
	}
}

// Snapshot returns latest federated policy.
func (f *Federator) Snapshot() FederatedPolicy {
	f.mu.RLock()
	s := f.snap
	f.mu.RUnlock()
	return s
}

var reRho = regexp.MustCompile(`^elite_predict_rho_projected\s+([0-9.eE+-]+)`)
var reOverload = regexp.MustCompile(`^elite_predict_overload_fraction\s+([0-9.eE+-]+)`)

func scrapeNode(metricsURL string) (rho, overload float64, ok bool) {
	resp, err := http.Get(metricsURL)
	if err != nil {
		return 0, 0, false
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return 0, 0, false
	}
	for _, line := range splitLines(string(body)) {
		if m := reRho.FindStringSubmatch(line); len(m) == 2 {
			rho, _ = strconv.ParseFloat(m[1], 64)
		}
		if m := reOverload.FindStringSubmatch(line); len(m) == 2 {
			overload, _ = strconv.ParseFloat(m[1], 64)
		}
	}
	return rho, overload, rho > 0 || overload > 0
}

func splitLines(s string) []string {
	var out []string
	start := 0
	for i := 0; i < len(s); i++ {
		if s[i] == '\n' {
			out = append(out, s[start:i])
			start = i + 1
		}
	}
	if start < len(s) {
		out = append(out, s[start:])
	}
	return out
}

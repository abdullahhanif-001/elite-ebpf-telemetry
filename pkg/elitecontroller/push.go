package elitecontroller

import (
	"bytes"
	"encoding/json"
	"log"
	"net/http"
	"time"
)

// PushConfig drives federation push to node agents.
type PushConfig struct {
	NodePushURLs []string // e.g. http://127.0.0.1:9102/internal/forecast/policy
	Token        string
	Interval     time.Duration
	RhoCap       float64
}

// Pusher polls metrics and pushes policy to nodes when overloaded.
type Pusher struct {
	cfg PushConfig
	fed *Federator
}

// NewPusher builds push controller.
func NewPusher(fed *Federator, cfg PushConfig) *Pusher {
	if cfg.Interval <= 0 {
		cfg.Interval = 500 * time.Millisecond
	}
	if cfg.RhoCap <= 0 {
		cfg.RhoCap = 0.85
	}
	return &Pusher{cfg: cfg, fed: fed}
}

// Run push loop until exit.
func (p *Pusher) Run() {
	if p == nil || len(p.cfg.NodePushURLs) == 0 {
		return
	}
	t := time.NewTicker(p.cfg.Interval)
	defer t.Stop()
	for range t.C {
		snap := p.fed.Snapshot()
		if snap.MaxRho < p.cfg.RhoCap && snap.MaxOverload < 0.5 {
			continue
		}
		body := map[string]interface{}{
			"fault":             snap.MaxRho >= p.cfg.RhoCap,
			"cause":             "network",
			"projected":         snap.MaxRho * 0.1,
			"ewma":              snap.MaxRho * 0.05,
			"overload_fraction": snap.MaxOverload,
			"shed_ppm":          uint32(snap.MaxOverload * 1_000_000),
			"rho_projected":     snap.MaxRho,
		}
		raw, _ := json.Marshal(body)
		for _, u := range p.cfg.NodePushURLs {
			req, err := http.NewRequest(http.MethodPost, u, bytes.NewReader(raw))
			if err != nil {
				continue
			}
			req.Header.Set("Content-Type", "application/json")
			if p.cfg.Token != "" {
				req.Header.Set("X-Elite-Policy-Token", p.cfg.Token)
			}
			resp, err := http.DefaultClient.Do(req)
			if err != nil {
				log.Printf("elite-controller push %s: %v", u, err)
				continue
			}
			resp.Body.Close()
		}
	}
}

package forecaster

import (
	"encoding/json"
	"os"
	"path/filepath"
	"time"
)

// DecisionBus is the shared predict → Soft DCIC handoff (ADR-004).
type DecisionBus struct {
	Fault     bool      `json:"fault"`
	Cause     string    `json:"cause"`
	Projected float64   `json:"projected"`
	EWMA      float64   `json:"ewma"`
	UpdatedAt time.Time `json:"updated_at"`
}

// WriteDecision persists the latest snapshot for elite-dcic to consume.
func WriteDecision(path string, snap Snapshot) error {
	if path == "" {
		return nil
	}
	_ = os.MkdirAll(filepath.Dir(path), 0o755)
	d := DecisionBus{
		Fault:     snap.Fault,
		Cause:     snap.Cause,
		Projected: snap.Projected,
		EWMA:      snap.EWMA,
		UpdatedAt: time.Now().UTC(),
	}
	b, err := json.Marshal(d)
	if err != nil {
		return err
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, b, 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

// ReadDecision loads the decision bus file.
func ReadDecision(path string) (DecisionBus, error) {
	var d DecisionBus
	b, err := os.ReadFile(path)
	if err != nil {
		return d, err
	}
	err = json.Unmarshal(b, &d)
	return d, err
}

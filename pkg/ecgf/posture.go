package ecgf

import (
	"encoding/json"
	"os"
	"time"

	"github.com/alibaba/kubeskoop/pkg/forecaster"
)

// Posture levels for ECGF-lite.
const (
	PostureObserve  = 0
	PostureTighten  = 1
	PostureIsolate  = 2
)

// State is the exported posture snapshot.
type State struct {
	Posture   int       `json:"posture"`
	Label     string    `json:"label"`
	Cause     string    `json:"cause"`
	Fault     bool      `json:"fault"`
	EWMA      float64   `json:"ewma"`
	Projected float64   `json:"projected"`
	UpdatedAt time.Time `json:"updated_at"`
	Source    string    `json:"source"`
}

// Compute maps a decision bus record to posture.
// HYPOTHESIS: fault → tighten; high projected relative to EWMA → isolate.
func Compute(d forecaster.DecisionBus) State {
	s := State{
		Posture:   PostureObserve,
		Label:     "observe",
		Cause:     d.Cause,
		Fault:     d.Fault,
		EWMA:      d.EWMA,
		Projected: d.Projected,
		UpdatedAt: time.Now().UTC(),
		Source:    "decision_bus",
	}
	if d.Fault {
		s.Posture = PostureTighten
		s.Label = "tighten"
	}
	if d.Fault && d.Projected > 0 && d.EWMA > 0 && d.Projected >= d.EWMA*1.5 {
		s.Posture = PostureIsolate
		s.Label = "isolate"
	}
	if d.Cause == "llc" || d.Cause == "mixed" {
		if s.Posture < PostureTighten {
			s.Posture = PostureTighten
			s.Label = "tighten"
		}
	}
	return s
}

// WriteState persists posture JSON for envelope scripts / Soft DCIC hints.
func WriteState(path string, s State) error {
	b, err := json.MarshalIndent(s, "", "  ")
	if err != nil {
		return err
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, b, 0o640); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

// ComputeFromJSON parses a loose decision-bus payload (ignores unknown fields / time formats).
func ComputeFromJSON(b []byte) (State, error) {
	var raw struct {
		Fault     bool    `json:"fault"`
		Cause     string  `json:"cause"`
		Projected float64 `json:"projected"`
		EWMA      float64 `json:"ewma"`
	}
	if err := json.Unmarshal(b, &raw); err != nil {
		return State{}, err
	}
	return Compute(forecaster.DecisionBus{
		Fault:     raw.Fault,
		Cause:     raw.Cause,
		Projected: raw.Projected,
		EWMA:      raw.EWMA,
	}), nil
}

// BEQuotaHint returns suggested BE CPU quota percent for Soft DCIC.
func BEQuotaHint(posture int) int {
	switch posture {
	case PostureIsolate:
		return 10
	case PostureTighten:
		return 25
	default:
		return 50
	}
}

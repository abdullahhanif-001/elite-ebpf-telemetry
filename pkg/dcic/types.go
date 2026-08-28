// Package dcic implements Soft (Track A) and Hard (Track B) deterministic
// cache-isolation control. Soft mode uses cgroup v2; Hard mode uses resctrl.
package dcic

import "time"

// Mode selects actuation strength.
const (
	ModeObserve = "observe" // metrics only
	ModeAdvise  = "advise"  // log intended actions
	ModeEnforce = "enforce" // apply cgroup / resctrl changes
)

// Track is selected by the capability gate.
const (
	TrackSoft = "A-soft"
	TrackHard = "B-hard"
)

// Config drives the Soft DCIC control loop.
type Config struct {
	Enabled      bool
	Mode         string
	Track        string
	Interval     time.Duration
	MetricsAddr  string // listen for Prometheus text
	NoiseURL     string // scrape target (physics / self)
	NoiseSeries  []string
	HardDrop     float64 // noise score trip (normalized 0-1 or latency seconds)
	Alpha        float64
	Window       int
	MinDwell     time.Duration // hysteresis
	SlackEpochs  int           // reclaim after N quiet epochs
	BEQuotaPct   int           // current BE cpu.max percent (1-100)
	BEQuotaFloor int           // never below this %
	BEQuotaCeil  int           // never above this %
	StepPct      int           // quota change per action
	LCCpus       string        // cpuset for latency-critical
	BECpus       string        // cpuset for best-effort
	CgroupRoot   string        // e.g. /sys/fs/cgroup/elite-dcic
	StatePath    string        // persist last action
}

// DefaultConfig returns production Soft DCIC defaults for DO/VPS guests.
func DefaultConfig() Config {
	return Config{
		Enabled:      true,
		Mode:         ModeObserve,
		Track:        TrackSoft,
		Interval:     time.Second,
		MetricsAddr:  "127.0.0.1:9103",
		NoiseURL:     "http://127.0.0.1:9103/metrics",
		NoiseSeries:  []string{"elite_dcic_noise_score", "elite_dcic_lc_latency_seconds"},
		HardDrop:     0.05, // 50ms LC latency trip when using latency series
		Alpha:        0.3,
		Window:       8,
		MinDwell:     3 * time.Second,
		SlackEpochs:  5,
		BEQuotaPct:   100,
		BEQuotaFloor: 10,
		BEQuotaCeil:  100,
		StepPct:      10,
		LCCpus:       "0-1",
		BECpus:       "2-3",
		CgroupRoot:   "/sys/fs/cgroup/elite-dcic",
		StatePath:    "/var/lib/elite/dcic-state.json",
	}
}

// Snapshot is a lock-free readable controller state for metrics.
type Snapshot struct {
	NoiseRaw     float64
	NoiseEWMA    float64
	Pressure     float64
	Fault        bool
	BEQuotaPct   int
	LastAction   string
	Mode         string
	Track        string
	EpochsSlack  int
	Samples      int
}

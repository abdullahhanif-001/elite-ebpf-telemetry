package forecaster

import (
	"sync"
	"time"
)

// EngineConfig tunes the EWMA + derivative projection loop.
type EngineConfig struct {
	Alpha          float64
	Window         int
	Horizon        time.Duration
	HardDrop       float64 // seconds
	AccThreshold   float64 // seconds^-2
	SampleInterval time.Duration
}

// DefaultEngineConfig returns production defaults from the plan.
func DefaultEngineConfig() EngineConfig {
	return EngineConfig{
		Alpha:          0.3,
		Window:         8,
		Horizon:        5 * time.Second,
		HardDrop:       0.1,
		AccThreshold:   0.001,
		SampleInterval: time.Second,
	}
}

// Snapshot is a lock-free readable copy of engine outputs.
type Snapshot struct {
	Raw          float64
	EWMA         float64
	Velocity     float64 // seconds / second
	Acceleration float64 // seconds / second^2
	Projected    float64 // seconds at horizon
	Fault        bool
	Cause        string // network|llc|psi|mixed|none
	Samples      int
	// Zero-buffer overload (Track D)
	OverloadFraction float64
	ShedPPM          uint32
	RhoProjected     float64
	ConnRate         float64
}

// Engine tracks latency with EWMA, velocity, and acceleration.
type Engine struct {
	tracker *KinematicTracker
	snap    Snapshot
	mu      sync.Mutex
}

// NewEngine builds an engine from cfg (zero fields filled from defaults).
func NewEngine(cfg EngineConfig) *Engine {
	d := DefaultEngineConfig()
	if cfg.Alpha == 0 {
		cfg.Alpha = d.Alpha
	}
	if cfg.Window == 0 {
		cfg.Window = d.Window
	}
	if cfg.Horizon == 0 {
		cfg.Horizon = d.Horizon
	}
	if cfg.HardDrop == 0 {
		cfg.HardDrop = d.HardDrop
	}
	if cfg.AccThreshold == 0 {
		cfg.AccThreshold = d.AccThreshold
	}
	if cfg.SampleInterval == 0 {
		cfg.SampleInterval = d.SampleInterval
	}
	return &Engine{
		tracker: NewKinematicTracker(KinematicConfig{
			Alpha:          cfg.Alpha,
			Window:         cfg.Window,
			Horizon:        cfg.Horizon,
			HardDrop:       cfg.HardDrop,
			AccThreshold:   cfg.AccThreshold,
			SampleInterval: cfg.SampleInterval,
		}),
	}
}

// Observe ingests one latency sample in seconds at time now.
func (e *Engine) Observe(raw float64, now time.Time) Snapshot {
	kin := e.tracker.Observe(raw, now)
	snap := Snapshot{
		Raw:          kin.Raw,
		EWMA:         kin.EWMA,
		Velocity:     kin.Velocity,
		Acceleration: kin.Acceleration,
		Projected:    kin.Projected,
		Fault:        kin.Fault,
		Cause:        CauseNone,
		Samples:      kin.Samples,
	}
	e.mu.Lock()
	e.snap = snap
	e.mu.Unlock()
	return snap
}

// Snapshot returns the latest computed state.
func (e *Engine) Snapshot() Snapshot {
	e.mu.Lock()
	s := e.snap
	e.mu.Unlock()
	return s
}

// ApplyOverload merges traffic overload into latency snapshot for export.
func ApplyOverload(snap *Snapshot, o OverloadSnapshot) {
	snap.OverloadFraction = o.Overload
	snap.ShedPPM = o.ShedPPM
	snap.RhoProjected = o.Traffic.RhoProjected
	snap.ConnRate = o.Traffic.LambdaEWMA
	if o.CombinedFault && !snap.Fault {
		snap.Fault = true
	}
}

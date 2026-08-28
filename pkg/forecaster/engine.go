package forecaster

import (
	"sync"
	"time"
)

// EngineConfig tunes the EWMA + derivative projection loop.
type EngineConfig struct {
	Alpha         float64
	Window        int
	Horizon       time.Duration
	HardDrop      float64 // seconds
	AccThreshold  float64 // seconds^-2
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
}

// Engine tracks latency with EWMA, velocity, and acceleration,
// projecting Horizon ahead when the series is accelerating upward.
type Engine struct {
	cfg EngineConfig

	mu       sync.Mutex
	ring     *Ring
	ewma     EWMA
	prevEWMA float64
	prevVel  float64
	havePrev bool
	lastAt   time.Time

	snap Snapshot
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
		cfg:  cfg,
		ring: NewRing(cfg.Window),
		ewma: NewEWMA(cfg.Alpha),
	}
}

// Observe ingests one latency sample in seconds at time now.
func (e *Engine) Observe(raw float64, now time.Time) Snapshot {
	e.mu.Lock()
	defer e.mu.Unlock()

	e.ring.Push(raw)
	s := e.ewma.Update(raw)

	var vel, acc float64
	if e.havePrev {
		dt := now.Sub(e.lastAt).Seconds()
		if dt <= 0 {
			dt = e.cfg.SampleInterval.Seconds()
			if dt <= 0 {
				dt = 1
			}
		}
		vel = (s - e.prevEWMA) / dt
		acc = (vel - e.prevVel) / dt
	}

	h := e.cfg.Horizon.Seconds()
	projected := s
	fault := false
	if e.havePrev && vel > 0 && acc > e.cfg.AccThreshold {
		// kinematic projection: s + v*t + 0.5*a*t^2
		projected = s + vel*h + 0.5*acc*h*h
		// Require EWMA already climbing (30% of hard drop) to reject flap false positives
		// while still tripping on real surges within one interval.
		if projected >= e.cfg.HardDrop && s >= e.cfg.HardDrop*0.3 {
			fault = true
		}
	} else if s >= e.cfg.HardDrop {
		// already over limit
		projected = s
		fault = true
	}

	e.prevVel = vel
	e.prevEWMA = s
	e.lastAt = now
	e.havePrev = true

	e.snap = Snapshot{
		Raw:          raw,
		EWMA:         s,
		Velocity:     vel,
		Acceleration: acc,
		Projected:    projected,
		Fault:        fault,
		Cause:        CauseNone,
		Samples:      e.ring.Len(),
	}
	return e.snap
}

// Snapshot returns the latest computed state.
func (e *Engine) Snapshot() Snapshot {
	e.mu.Lock()
	s := e.snap
	e.mu.Unlock()
	return s
}

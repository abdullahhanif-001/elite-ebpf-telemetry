package forecaster

import (
	"sync"
	"time"
)

// KinematicConfig tunes EWMA + derivative projection.
type KinematicConfig struct {
	Alpha          float64
	Window         int
	Horizon        time.Duration
	HardDrop       float64
	AccThreshold   float64
	SampleInterval time.Duration
	UseRingLS      bool // least-squares velocity from ring when true
}

// KinematicSnapshot is the output of one Observe tick.
type KinematicSnapshot struct {
	Raw          float64
	EWMA         float64
	Velocity     float64
	Acceleration float64
	Projected    float64
	Fault        bool
	Samples      int
}

// KinematicTracker implements EWMA + kinematic projection: s + v·h + ½a·h².
type KinematicTracker struct {
	cfg KinematicConfig

	mu       sync.Mutex
	ring     *Ring
	ewma     EWMA
	prevEWMA float64
	prevVel  float64
	havePrev bool
	lastAt   time.Time
}

// NewKinematicTracker builds a tracker with defaults for zero fields.
func NewKinematicTracker(cfg KinematicConfig) *KinematicTracker {
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
	return &KinematicTracker{
		cfg:  cfg,
		ring: NewRing(cfg.Window),
		ewma: NewEWMA(cfg.Alpha),
	}
}

// Observe ingests one sample at time now.
func (k *KinematicTracker) Observe(raw float64, now time.Time) KinematicSnapshot {
	k.mu.Lock()
	defer k.mu.Unlock()

	k.ring.Push(raw)
	s := k.ewma.Update(raw)

	var vel, acc float64
	if k.havePrev {
		dt := now.Sub(k.lastAt).Seconds()
		if dt <= 0 {
			dt = k.cfg.SampleInterval.Seconds()
			if dt <= 0 {
				dt = 1
			}
		}
		if k.cfg.UseRingLS && k.ring.Len() >= 3 {
			vel = k.ring.VelocityLS(dt)
			acc = (vel - k.prevVel) / dt
		} else {
			vel = (s - k.prevEWMA) / dt
			acc = (vel - k.prevVel) / dt
		}
	}

	h := k.cfg.Horizon.Seconds()
	projected := s
	fault := false
	if k.havePrev && vel > 0 && acc > k.cfg.AccThreshold {
		projected = s + vel*h + 0.5*acc*h*h
		if projected >= k.cfg.HardDrop && s >= k.cfg.HardDrop*0.3 {
			fault = true
		}
	} else if s >= k.cfg.HardDrop {
		projected = s
		fault = true
	}

	k.prevVel = vel
	k.prevEWMA = s
	k.lastAt = now
	k.havePrev = true

	return KinematicSnapshot{
		Raw:          raw,
		EWMA:         s,
		Velocity:     vel,
		Acceleration: acc,
		Projected:    projected,
		Fault:        fault,
		Samples:      k.ring.Len(),
	}
}

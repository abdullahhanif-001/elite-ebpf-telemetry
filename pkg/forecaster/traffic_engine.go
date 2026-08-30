package forecaster

import (
	"sync"
	"time"
)

const ppmScale = 1_000_000

// TrafficConfig tunes connection-rate kinematics and ρ projection.
type TrafficConfig struct {
	Horizon        time.Duration
	RhoTarget      float64 // utilization target (e.g. 0.7)
	MuEst          float64 // estimated max stable conn/s
	Gamma          float64 // shed curve exponent (≥1)
	SampleInterval time.Duration
	Window         int
	Alpha          float64
	AccThreshold   float64
}

// DefaultTrafficConfig returns production defaults.
func DefaultTrafficConfig() TrafficConfig {
	return TrafficConfig{
		Horizon:        5 * time.Second,
		RhoTarget:      0.7,
		MuEst:          1000.0,
		Gamma:          2.0,
		SampleInterval: time.Second,
		Window:         8,
		Alpha:          0.3,
		AccThreshold:   0.001,
	}
}

// TrafficSnapshot holds connection-rate physics outputs.
type TrafficSnapshot struct {
	ConnCount    float64
	LambdaEWMA   float64 // conn/s
	Velocity     float64
	Acceleration float64
	RhoNow       float64
	RhoProjected float64
	Overload     float64 // 0..1
	PreFault     bool
}

// TrafficEngine tracks λ and projects ρ = λ/μ.
type TrafficEngine struct {
	cfg     TrafficConfig
	tracker *KinematicTracker

	mu       sync.Mutex
	prevConn float64
	havePrev bool
	lastAt   time.Time
	lastSnap TrafficSnapshot
}

// NewTrafficEngine builds a traffic engine.
func NewTrafficEngine(cfg TrafficConfig) *TrafficEngine {
	d := DefaultTrafficConfig()
	if cfg.RhoTarget <= 0 {
		cfg.RhoTarget = d.RhoTarget
	}
	if cfg.MuEst <= 0 {
		cfg.MuEst = d.MuEst
	}
	if cfg.Gamma <= 0 {
		cfg.Gamma = d.Gamma
	}
	if cfg.Horizon <= 0 {
		cfg.Horizon = d.Horizon
	}
	if cfg.Window <= 0 {
		cfg.Window = d.Window
	}
	if cfg.Alpha <= 0 {
		cfg.Alpha = d.Alpha
	}
	if cfg.AccThreshold <= 0 {
		cfg.AccThreshold = d.AccThreshold
	}
	if cfg.SampleInterval <= 0 {
		cfg.SampleInterval = d.SampleInterval
	}
	te := &TrafficEngine{
		cfg: cfg,
		tracker: NewKinematicTracker(KinematicConfig{
			Alpha:          cfg.Alpha,
			Window:         cfg.Window,
			Horizon:        cfg.Horizon,
			HardDrop:       cfg.MuEst * cfg.RhoTarget,
			AccThreshold:   cfg.AccThreshold,
			SampleInterval: cfg.SampleInterval,
			UseRingLS:      true,
		}),
	}
	return te
}

// SetMuEst updates live service rate estimate.
func (te *TrafficEngine) SetMuEst(mu float64) {
	if te == nil || mu <= 0 {
		return
	}
	te.mu.Lock()
	te.cfg.MuEst = mu
	te.mu.Unlock()
}

// ObserveLambda ingests direct connection/packet rate (conn/s or pkt/s proxy).
func (te *TrafficEngine) ObserveLambda(lambda float64, now time.Time) TrafficSnapshot {
	te.mu.Lock()
	defer te.mu.Unlock()

	kin := te.tracker.Observe(lambda, now)
	mu := te.cfg.MuEst
	if mu <= 0 {
		mu = 1
	}
	rhoNow := kin.EWMA / mu
	rhoProj := kin.Projected / mu
	overload := ComputeOverloadFraction(rhoProj, te.cfg.RhoTarget)
	preFault := rhoProj > te.cfg.RhoTarget && rhoNow > te.cfg.RhoTarget*0.3

	te.lastSnap = TrafficSnapshot{
		ConnCount:    lambda,
		LambdaEWMA:   kin.EWMA,
		Velocity:     kin.Velocity,
		Acceleration: kin.Acceleration,
		RhoNow:       rhoNow,
		RhoProjected: rhoProj,
		Overload:     overload,
		PreFault:     preFault,
	}
	return te.lastSnap
}

// ObserveConn ingests established connection count at time now.
func (te *TrafficEngine) ObserveConn(connCount float64, now time.Time) TrafficSnapshot {
	te.mu.Lock()
	defer te.mu.Unlock()

	var lambda float64
	if te.havePrev {
		dt := now.Sub(te.lastAt).Seconds()
		if dt <= 0 {
			dt = te.cfg.SampleInterval.Seconds()
		}
		if dt > 0 {
			delta := connCount - te.prevConn
			if delta < 0 {
				delta = 0
			}
			lambda = delta / dt
		}
	}
	te.prevConn = connCount
	te.lastAt = now
	te.havePrev = true

	kin := te.tracker.Observe(lambda, now)
	mu := te.cfg.MuEst
	if mu <= 0 {
		mu = 1
	}
	rhoNow := kin.EWMA / mu
	rhoProj := kin.Projected / mu
	overload := ComputeOverloadFraction(rhoProj, te.cfg.RhoTarget)
	preFault := rhoProj > te.cfg.RhoTarget && rhoNow > te.cfg.RhoTarget*0.3

	te.lastSnap = TrafficSnapshot{
		ConnCount:    connCount,
		LambdaEWMA:   kin.EWMA,
		Velocity:     kin.Velocity,
		Acceleration: kin.Acceleration,
		RhoNow:       rhoNow,
		RhoProjected: rhoProj,
		Overload:     overload,
		PreFault:     preFault,
	}
	return te.lastSnap
}

// Snapshot returns last traffic snapshot.
func (te *TrafficEngine) Snapshot() TrafficSnapshot {
	te.mu.Lock()
	s := te.lastSnap
	te.mu.Unlock()
	return s
}

// ComputeOverloadFraction maps projected ρ to [0,1] shed fraction.
func ComputeOverloadFraction(rhoProj, rhoTarget float64) float64 {
	if rhoTarget <= 0 || rhoTarget >= 1 {
		rhoTarget = 0.7
	}
	if rhoProj <= rhoTarget {
		return 0
	}
	o := (rhoProj - rhoTarget) / (1.0 - rhoTarget)
	if o > 1 {
		return 1
	}
	if o < 0 {
		return 0
	}
	return o
}

// ShedPPM converts overload to parts-per-million drop probability.
func ShedPPM(overload, gamma float64) uint32 {
	if overload <= 0 {
		return 0
	}
	if gamma <= 0 {
		gamma = 2
	}
	x := overload
	for i := 1; i < int(gamma); i++ {
		x *= overload
	}
	p := x * float64(ppmScale)
	if p > float64(ppmScale) {
		return ppmScale
	}
	return uint32(p)
}

package forecaster

import (
	"sync"
	"time"
)

// MuEstimator tracks live μ from XDP pass rate during low overload.
type MuEstimator struct {
	mu          sync.Mutex
	lastPass    uint64
	lastAt      time.Time
	muEst       float64
	minSamples  int
	sampleCount int
}

// NewMuEstimator builds estimator with floor default.
func NewMuEstimator(floor float64) *MuEstimator {
	if floor <= 0 {
		floor = 1000
	}
	return &MuEstimator{muEst: floor, minSamples: 3}
}

// Observe updates μ from pass counter delta when overload is low.
func (m *MuEstimator) Observe(stats XDPStats, overload float64, now time.Time) float64 {
	if m == nil {
		return 0
	}
	m.mu.Lock()
	defer m.mu.Unlock()

	if m.lastAt.IsZero() {
		m.lastPass = stats.Pass
		m.lastAt = now
		return m.muEst
	}
	dt := now.Sub(m.lastAt).Seconds()
	if dt < 0.05 {
		return m.muEst
	}
	delta := stats.Pass - m.lastPass
	m.lastPass = stats.Pass
	m.lastAt = now
	if overload > 0.5 || delta == 0 {
		return m.muEst
	}
	rate := float64(delta) / dt
	m.sampleCount++
	if m.sampleCount >= m.minSamples {
		m.muEst = 0.7*m.muEst + 0.3*rate
	}
	return m.muEst
}

// Value returns current μ estimate.
func (m *MuEstimator) Value() float64 {
	if m == nil {
		return 1000
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.muEst
}

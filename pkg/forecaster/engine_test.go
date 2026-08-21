package forecaster

import (
	"testing"
	"time"
)

func TestEngineFlatSeriesNoFault(t *testing.T) {
	e := NewEngine(EngineConfig{
		Alpha:          0.5,
		Window:         8,
		Horizon:        5 * time.Second,
		HardDrop:       0.1,
		AccThreshold:   0.001,
		SampleInterval: time.Second,
	})
	now := time.Unix(0, 0)
	for i := 0; i < 10; i++ {
		s := e.Observe(0.01, now.Add(time.Duration(i)*time.Second))
		if s.Fault {
			t.Fatalf("flat series should not fault at step %d: %+v", i, s)
		}
	}
}

func TestEngineRisingLatencyFaults(t *testing.T) {
	e := NewEngine(EngineConfig{
		Alpha:          0.5,
		Window:         8,
		Horizon:        5 * time.Second,
		HardDrop:       0.1,
		AccThreshold:   0.0001,
		SampleInterval: time.Second,
	})
	now := time.Unix(0, 0)
	// Quadratic-ish surge so acceleration stays positive.
	vals := []float64{0.01, 0.02, 0.04, 0.07, 0.11, 0.16, 0.22, 0.30}
	var last Snapshot
	for i, v := range vals {
		last = e.Observe(v, now.Add(time.Duration(i)*time.Second))
	}
	if !last.Fault {
		t.Fatalf("expected fault on rising surge, got %+v", last)
	}
	if last.Projected < 0.1 {
		t.Fatalf("projected %.4f should be >= hard drop", last.Projected)
	}
	if last.Velocity <= 0 {
		t.Fatalf("expected positive velocity, got %v", last.Velocity)
	}
}

func TestRingNoAllocSnapshot(t *testing.T) {
	r := NewRing(4)
	r.Push(1)
	r.Push(2)
	r.Push(3)
	dst := make([]float64, 4)
	n := r.Snapshot(dst)
	if n != 3 {
		t.Fatalf("len=%d want 3", n)
	}
	if dst[0] != 1 || dst[2] != 3 {
		t.Fatalf("order wrong: %v", dst[:n])
	}
	r.Push(4)
	r.Push(5)
	n = r.Snapshot(dst)
	if n != 4 || dst[0] != 2 || dst[3] != 5 {
		t.Fatalf("wrap order wrong: n=%d %v", n, dst[:n])
	}
}

func TestEWMAConverges(t *testing.T) {
	e := NewEWMA(0.5)
	e.Update(10)
	v := e.Update(0)
	if v < 4.9 || v > 5.1 {
		t.Fatalf("ewma=%v want ~5", v)
	}
}

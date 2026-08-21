package forecaster

import (
	"context"
	"sync"
	"testing"
	"time"
)

type staticScraper struct {
	v   float64
	err error
}

func (s *staticScraper) Sample(time.Time) (float64, error) {
	return s.v, s.err
}

type recordShedder struct {
	mu       sync.Mutex
	shedN    int
	restoreN int
	probes   []string
}

func (r *recordShedder) ShedEvents(context.Context) error {
	r.mu.Lock()
	r.shedN++
	r.mu.Unlock()
	return nil
}

func (r *recordShedder) RestoreEvents(context.Context) error {
	r.mu.Lock()
	r.restoreN++
	r.mu.Unlock()
	return nil
}

func TestSemiShedAndRestore(t *testing.T) {
	sh := &recordShedder{probes: []string{"socketlatency", "packetloss"}}
	r, coll := NewRunner(Config{
		Enabled:         true,
		Interval:        time.Second,
		Horizon:         5 * time.Second,
		Window:          8,
		Alpha:           0.5,
		HardDropSeconds: 0.1,
		AccThreshold:    0.0001,
		Mode:            ModeSemi,
		SemiCooldown:    60 * time.Millisecond, // short for test
		Targets:         []Target{{URL: "http://127.0.0.1:9/metrics", Series: []string{"x"}}},
	}, sh)
	if coll == nil {
		t.Fatal("collector nil")
	}
	r.scraper = &staticScraper{v: 0.002}

	ctx := context.Background()
	now := time.Unix(0, 0)
	// warm
	r.applySample(ctx, 0.002, now)
	now = now.Add(time.Second)
	r.applySample(ctx, 0.002, now)

	// surge to fault
	for _, v := range []float64{0.05, 0.12, 0.25} {
		now = now.Add(time.Second)
		r.applySample(ctx, v, now)
	}

	sh.mu.Lock()
	shed := sh.shedN
	sh.mu.Unlock()
	if shed < 1 {
		t.Fatalf("expected ShedEvents on fault, shedN=%d", shed)
	}

	// advance past cooldown and tick restore path
	now = now.Add(100 * time.Millisecond)
	r.applySample(ctx, 0.01, now)

	sh.mu.Lock()
	rest := sh.restoreN
	sh.mu.Unlock()
	if rest < 1 {
		t.Fatalf("expected RestoreEvents after cooldown, restoreN=%d", rest)
	}
	if len(sh.probes) != 2 {
		t.Fatalf("probe identity lost: %v", sh.probes)
	}
}

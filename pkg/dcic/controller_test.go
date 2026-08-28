package dcic

import (
	"fmt"
	"testing"
	"time"
)

func TestControllerShrinkOnNoise(t *testing.T) {
	cfg := DefaultConfig()
	cfg.Mode = ModeEnforce
	cfg.HardDrop = 0.05
	cfg.MinDwell = 0
	cfg.BEQuotaPct = 100
	cfg.StepPct = 10
	c := NewController(cfg)
	now := time.Now()
	d := c.Observe(0.2, 0, now)
	if d.Action != "shrink_be" {
		t.Fatalf("want shrink_be got %s", d.Action)
	}
	if d.BEQuotaPct != 90 {
		t.Fatalf("want quota 90 got %d", d.BEQuotaPct)
	}
}

func TestControllerObserveDoesNotMutate(t *testing.T) {
	cfg := DefaultConfig()
	cfg.Mode = ModeObserve
	cfg.HardDrop = 0.05
	cfg.MinDwell = 0
	cfg.BEQuotaPct = 100
	c := NewController(cfg)
	d := c.Observe(0.2, 0, time.Now())
	if d.Action != "observe_would_shrink_be" {
		t.Fatalf("got %s", d.Action)
	}
	if c.BEQuota() != 100 {
		t.Fatalf("observe mutated quota to %d", c.BEQuota())
	}
}

func TestControllerReclaimOnSlack(t *testing.T) {
	cfg := DefaultConfig()
	cfg.Mode = ModeEnforce
	cfg.HardDrop = 0.05
	cfg.MinDwell = 0
	cfg.SlackEpochs = 3
	cfg.BEQuotaPct = 50
	cfg.StepPct = 10
	c := NewController(cfg)
	now := time.Now()
	sawReclaim := false
	var last Decision
	for i := 0; i < 5; i++ {
		last = c.Observe(0.001, 0, now.Add(time.Duration(i)*time.Second))
		if last.Action == "reclaim_be" {
			sawReclaim = true
			if last.BEQuotaPct != 60 {
				t.Fatalf("want 60 got %d", last.BEQuotaPct)
			}
		}
	}
	if !sawReclaim {
		t.Fatalf("want reclaim_be in loop got last=%s reason=%s quota=%d", last.Action, last.Reason, last.BEQuotaPct)
	}
	if c.BEQuota() < 60 {
		t.Fatalf("quota not raised: %d", c.BEQuota())
	}
}

func TestControllerHysteresisBlocksRapidOscillation(t *testing.T) {
	cfg := DefaultConfig()
	cfg.Mode = ModeEnforce
	cfg.HardDrop = 0.05
	cfg.MinDwell = 5 * time.Second
	cfg.BEQuotaPct = 100
	c := NewController(cfg)
	t0 := time.Now()
	d1 := c.Observe(0.2, 0, t0)
	if d1.Action != "shrink_be" {
		t.Fatalf("first: %s", d1.Action)
	}
	d2 := c.Observe(0.2, 0, t0.Add(time.Second))
	if d2.Action != "none" && d2.Reason != "dwell_or_noop" {
		// second action must be blocked by dwell
		if d2.Action == "shrink_be" {
			t.Fatalf("dwell failed: second shrink")
		}
	}
}

func TestDefaultConfigTrackSoft(t *testing.T) {
	cfg := DefaultConfig()
	if cfg.Track != TrackSoft {
		t.Fatal(cfg.Track)
	}
	if fmt.Sprint(cfg.Mode) != ModeObserve {
		t.Fatal(cfg.Mode)
	}
}

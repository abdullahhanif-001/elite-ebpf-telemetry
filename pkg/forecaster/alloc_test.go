package forecaster

import (
	"testing"
	"time"
)

func TestAllocsRingPush(t *testing.T) {
	r := NewRing(8)
	avg := testing.AllocsPerRun(1000, func() {
		r.Push(0.01)
	})
	if avg != 0 {
		t.Fatalf("Ring.Push allocs/op=%v want 0", avg)
	}
}

func TestAllocsEWMAUpdate(t *testing.T) {
	e := NewEWMA(0.3)
	avg := testing.AllocsPerRun(1000, func() {
		e.Update(0.02)
	})
	if avg != 0 {
		t.Fatalf("EWMA.Update allocs/op=%v want 0", avg)
	}
}

func TestAllocsEngineObserve(t *testing.T) {
	eng := NewEngine(DefaultEngineConfig())
	now := time.Unix(1, 0)
	avg := testing.AllocsPerRun(1000, func() {
		now = now.Add(time.Second)
		_ = eng.Observe(0.01, now)
	})
	if avg != 0 {
		t.Fatalf("Engine.Observe allocs/op=%v want 0", avg)
	}
}

func TestAllocsParseBody(t *testing.T) {
	body := []byte("softirq_wait_seconds_sum 2.0\nsoftirq_wait_seconds_count 10\n")
	s := NewScraper(nil)
	prefixes := [][]byte{[]byte("softirq_wait_seconds")}
	// warm
	_, _ = s.ParseBody(body, prefixes)
	avg := testing.AllocsPerRun(1000, func() {
		_, _ = s.ParseBody(body, prefixes)
	})
	if avg != 0 {
		t.Fatalf("ParseBody allocs/op=%v want 0", avg)
	}
}

func TestAllocsParseMetricLineBytes(t *testing.T) {
	line := []byte(`softirq_wait_seconds_sum{cpu="0"} 1.5`)
	avg := testing.AllocsPerRun(1000, func() {
		_, _, _ = parseMetricLineBytes(line)
	})
	if avg != 0 {
		t.Fatalf("parseMetricLineBytes allocs/op=%v want 0", avg)
	}
}

package forecaster

import (
	"math"
	"testing"
	"time"
)

// Retina-beat gates: absolute Elite targets for SWITCH_READY scorecard.

func TestCompeteForecastLeadSurge(t *testing.T) {
	e := NewEngine(EngineConfig{
		Alpha: 0.5, Window: 8, Horizon: 5 * time.Second,
		HardDrop: 0.1, AccThreshold: 0.0001, SampleInterval: time.Second,
	})
	now := time.Unix(0, 0)
	_ = e.Observe(0.002, now)
	now = now.Add(time.Second)
	_ = e.Observe(0.002, now)

	delay := -1
	for i, v := range []float64{0.03, 0.09, 0.25} {
		now = now.Add(time.Second)
		s := e.Observe(v, now)
		if s.Fault {
			delay = i
			if s.Projected < 0.1 && s.EWMA < 0.1 {
				t.Fatalf("fault without projection/ewma over hardDrop: %+v", s)
			}
			break
		}
	}
	if delay < 0 || delay > 2 {
		t.Fatalf("surge_fault_delay_intervals=%d want 0..2", delay)
	}
}

func TestCompeteFaultPrecisionFlat(t *testing.T) {
	e := NewEngine(DefaultEngineConfig())
	now := time.Unix(0, 0)
	edges := 0
	prev := false
	for i := 0; i < 30; i++ {
		s := e.Observe(0.01, now.Add(time.Duration(i)*time.Second))
		if s.Fault && !prev {
			edges++
		}
		prev = s.Fault
	}
	if edges != 0 {
		t.Fatalf("flat_false_positives=%d want 0", edges)
	}
}

func TestCompeteEWMADampening(t *testing.T) {
	e := NewEngine(EngineConfig{
		Alpha: 0.3, Window: 8, Horizon: 5 * time.Second,
		HardDrop: 0.1, AccThreshold: 0.001, SampleInterval: time.Second,
	})
	now := time.Unix(0, 0)
	var raws, ewmas []float64
	for i := 0; i < 40; i++ {
		v := 0.01
		if i%2 == 0 {
			v = 0.02
		}
		s := e.Observe(v, now.Add(time.Duration(i)*time.Second))
		raws = append(raws, v)
		ewmas = append(ewmas, s.EWMA)
	}
	rawSD := stddev(raws)
	ewmaSD := stddev(ewmas)
	if rawSD <= 0 {
		t.Fatal("raw stddev=0")
	}
	ratio := ewmaSD / rawSD
	if ratio >= 0.30 {
		t.Fatalf("ewma_dampen_ratio=%.3f want <0.30 (ewmaSD=%.4f rawSD=%.4f)", ratio, ewmaSD, rawSD)
	}
}

func TestCompeteParseThroughput(t *testing.T) {
	line := []byte(`softirq_wait_seconds_sum{cpu="0"} 1.2345`)
	const target = 100_000
	// Warm
	_, _, _ = parseMetricLineBytes(line)

	start := time.Now()
	n := 0
	for time.Since(start) < 200*time.Millisecond {
		for i := 0; i < 1000; i++ {
			_, _, _ = parseMetricLineBytes(line)
			n++
		}
	}
	elapsed := time.Since(start).Seconds()
	ops := float64(n) / elapsed
	if ops < target {
		t.Fatalf("parse_ops_s=%.0f want >=%d", ops, target)
	}
}

func stddev(xs []float64) float64 {
	if len(xs) == 0 {
		return 0
	}
	var sum float64
	for _, x := range xs {
		sum += x
	}
	mean := sum / float64(len(xs))
	var ss float64
	for _, x := range xs {
		d := x - mean
		ss += d * d
	}
	return math.Sqrt(ss / float64(len(xs)))
}

func BenchmarkCompeteEngineObserveNS(b *testing.B) {
	e := NewEngine(DefaultEngineConfig())
	now := time.Unix(1, 0)
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		now = now.Add(time.Nanosecond)
		_ = e.Observe(0.012, now)
	}
}

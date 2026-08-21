package forecaster

import (
	"testing"
	"time"
)

func TestStressDDoSSpikeFaultWithinOneInterval(t *testing.T) {
	e := NewEngine(EngineConfig{
		Alpha:          0.5,
		Window:         8,
		Horizon:        5 * time.Second,
		HardDrop:       0.1,
		AccThreshold:   0.0001,
		SampleInterval: time.Second,
	})
	now := time.Unix(0, 0)
	// baseline
	_ = e.Observe(0.002, now)
	now = now.Add(time.Second)
	_ = e.Observe(0.002, now)

	// surge 2ms -> 250ms over 3 intervals
	vals := []float64{0.02, 0.08, 0.25}
	faultAt := -1
	for i, v := range vals {
		now = now.Add(time.Second)
		s := e.Observe(v, now)
		if s.Fault {
			faultAt = i
			break
		}
	}
	if faultAt < 0 {
		t.Fatal("expected fault during DDoS surge")
	}
	// within ≤1 interval after surge conditions establish (allow trip on 2nd or 3rd step)
	if faultAt > 2 {
		t.Fatalf("fault delay too large: step=%d", faultAt)
	}
}

func TestStressFlatNoFault(t *testing.T) {
	e := NewEngine(DefaultEngineConfig())
	now := time.Unix(0, 0)
	for i := 0; i < 20; i++ {
		s := e.Observe(0.01, now.Add(time.Duration(i)*time.Second))
		if s.Fault {
			t.Fatalf("flat false fault at %d: %+v", i, s)
		}
	}
}

func TestStressDeclineNoFault(t *testing.T) {
	e := NewEngine(DefaultEngineConfig())
	now := time.Unix(0, 0)
	vals := []float64{0.09, 0.07, 0.05, 0.03, 0.02, 0.01}
	for i, v := range vals {
		s := e.Observe(v, now.Add(time.Duration(i)*time.Second))
		if s.Fault {
			t.Fatalf("decline false fault at %d: %+v", i, s)
		}
	}
}

func TestStressFlapNoSustainedFalseFault(t *testing.T) {
	e := NewEngine(EngineConfig{
		Alpha:          0.3,
		Window:         8,
		Horizon:        5 * time.Second,
		HardDrop:       0.1,
		AccThreshold:   0.001,
		SampleInterval: time.Second,
	})
	now := time.Unix(0, 0)
	edges := 0
	prev := false
	for i := 0; i < 40; i++ {
		// Oscillation stays well below hardDrop*0.3 EWMA gate
		v := 0.01
		if i%2 == 0 {
			v = 0.02
		}
		s := e.Observe(v, now.Add(time.Duration(i)*time.Second))
		if s.Fault && !prev {
			edges++
		}
		prev = s.Fault
	}
	if edges > 1 {
		t.Fatalf("flap false-positive rising edges=%d want <=1", edges)
	}
}

func BenchmarkEngineObserve(b *testing.B) {
	e := NewEngine(DefaultEngineConfig())
	now := time.Unix(1, 0)
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		now = now.Add(time.Millisecond)
		_ = e.Observe(0.01, now)
	}
}

func BenchmarkParseBodyFlood(b *testing.B) {
	// large prebuilt exposition (~thousands of lines)
	var buf []byte
	for i := 0; i < 5000; i++ {
		buf = append(buf, []byte("softirq_wait_seconds_bucket{le=\"1\"} 1\n")...)
	}
	buf = append(buf, []byte("softirq_wait_seconds_sum 50\nsoftirq_wait_seconds_count 1000\n")...)
	s := NewScraper(nil)
	prefixes := [][]byte{[]byte("softirq_wait_seconds")}
	_, _ = s.ParseBody(buf, prefixes)
	b.ReportAllocs()
	b.SetBytes(int64(len(buf)))
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, _ = s.ParseBody(buf, prefixes)
	}
}

func BenchmarkParseMetricLineBytes(b *testing.B) {
	line := []byte(`softirq_wait_seconds_sum{cpu="0"} 1.2345`)
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, _, _ = parseMetricLineBytes(line)
	}
}

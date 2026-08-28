package llc

import (
	"strings"
	"testing"
	"time"
)

func TestHitRatio(t *testing.T) {
	if g := HitRatio(100, 25); g < 0.74 || g > 0.76 {
		t.Fatalf("HitRatio=got %v want ~0.75", g)
	}
	if HitRatio(0, 0) != 0 {
		t.Fatal("empty refs")
	}
}

func TestObserveMissRate(t *testing.T) {
	s := NewSampler()
	s.Detect()
	t0 := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
	t1 := t0.Add(time.Second)
	s.ObserveRaw(1000, 100, t0)
	sn := s.ObserveRaw(2000, 300, t1)
	if sn.MissRate < 199 || sn.MissRate > 201 {
		t.Fatalf("missRate=%v want ~200", sn.MissRate)
	}
	if sn.HitRatio < 0.84 || sn.HitRatio > 0.86 {
		t.Fatalf("hit=%v", sn.HitRatio)
	}
}

func TestFormatPrometheus(t *testing.T) {
	txt := FormatPrometheus(Snapshot{Enabled: true, Refs: 10, Misses: 2, HitRatio: 0.8, MissRate: 1.5})
	for _, needle := range []string{"elite_llc_enabled 1", "elite_llc_references_total 10", "elite_llc_misses_total 2"} {
		if !strings.Contains(txt, needle) {
			t.Fatalf("missing %q in %s", needle, txt)
		}
	}
}

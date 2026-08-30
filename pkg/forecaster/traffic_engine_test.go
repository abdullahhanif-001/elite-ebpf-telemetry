package forecaster

import (
	"testing"
	"time"
)

func TestComputeOverloadFraction(t *testing.T) {
	if o := ComputeOverloadFraction(0.5, 0.7); o != 0 {
		t.Fatalf("got %v", o)
	}
	if o := ComputeOverloadFraction(0.85, 0.7); o <= 0 {
		t.Fatalf("got %v want >0", o)
	}
	if o := ComputeOverloadFraction(1.5, 0.7); o != 1 {
		t.Fatalf("got %v want 1", o)
	}
}

func TestShedPPM(t *testing.T) {
	if ShedPPM(0, 2) != 0 {
		t.Fatal("zero overload")
	}
	p := ShedPPM(0.5, 2.0)
	if p == 0 || p > ppmScale {
		t.Fatalf("ppm=%d", p)
	}
}

func TestTrafficEnginePreFault(t *testing.T) {
	te := NewTrafficEngine(DefaultTrafficConfig())
	now := time.Now()
	te.ObserveConn(100, now)
	s1 := te.ObserveConn(200, now.Add(time.Second))
	if s1.LambdaEWMA <= 0 {
		t.Fatalf("lambda=%v", s1.LambdaEWMA)
	}
	// ramp connections
	for i := 0; i < 5; i++ {
		te.ObserveConn(float64(200+i*150), now.Add(time.Duration(i+2)*time.Second))
	}
	s := te.Snapshot()
	if s.RhoProjected <= 0 {
		t.Fatalf("rho_proj=%v", s.RhoProjected)
	}
}

func TestFuseOverload(t *testing.T) {
	lat := Snapshot{Fault: false, EWMA: 0.01, Projected: 0.02}
	tr := TrafficSnapshot{RhoProjected: 0.85, Overload: 0.5, PreFault: true}
	o := FuseOverload(lat, tr, 2.0)
	if !o.CombinedFault {
		t.Fatal("expected combined fault")
	}
	if o.ShedPPM == 0 {
		t.Fatal("expected shed ppm")
	}
}

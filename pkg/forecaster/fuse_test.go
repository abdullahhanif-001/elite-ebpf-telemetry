package forecaster

import "testing"

func TestBlameCauseNetwork(t *testing.T) {
	v := SignalVector{Network: 0.2, HasLLC: true, LLC: 0.01, HasPSI: false}
	if g := BlameCause(v, 0.1); g != CauseNetwork {
		t.Fatalf("got %s want network", g)
	}
}

func TestBlameCauseLLC(t *testing.T) {
	v := SignalVector{Network: 0.01, HasLLC: true, LLC: 0.25}
	if g := BlameCause(v, 0.1); g != CauseLLC {
		t.Fatalf("got %s want llc", g)
	}
}

func TestBlameCauseMixed(t *testing.T) {
	v := SignalVector{Network: 0.2, HasLLC: true, LLC: 0.18}
	if g := BlameCause(v, 0.1); g != CauseMixed {
		t.Fatalf("got %s want mixed", g)
	}
}

func TestFuseScalar(t *testing.T) {
	v := SignalVector{Network: 0.1, HasLLC: true, LLC: 0.2, HasPSI: true, PSI: 0.0}
	w := FuseWeights{Network: 0.5, LLC: 0.5, PSI: 0}
	got := FuseScalar(v, w)
	if got < 0.14 || got > 0.16 {
		t.Fatalf("fuse=%v", got)
	}
}

func TestShouldShedEvents(t *testing.T) {
	if !ShouldShedEvents(CauseNetwork) || !ShouldShedEvents(CauseMixed) {
		t.Fatal("shed network/mixed")
	}
	if ShouldShedEvents(CauseLLC) || ShouldShedEvents(CausePSI) {
		t.Fatal("do not shed llc/psi-only")
	}
}

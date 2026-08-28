package ecgf

import (
	"testing"

	"github.com/alibaba/kubeskoop/pkg/forecaster"
)

func TestComputeObserve(t *testing.T) {
	s := Compute(forecaster.DecisionBus{Fault: false, Cause: "network", Projected: 0.01, EWMA: 0.01})
	if s.Posture != PostureObserve {
		t.Fatalf("got %d", s.Posture)
	}
}

func TestComputeTighten(t *testing.T) {
	s := Compute(forecaster.DecisionBus{Fault: true, Cause: "network", Projected: 0.1, EWMA: 0.08})
	if s.Posture != PostureTighten {
		t.Fatalf("got %d want tighten", s.Posture)
	}
}

func TestComputeIsolate(t *testing.T) {
	s := Compute(forecaster.DecisionBus{Fault: true, Cause: "network", Projected: 0.2, EWMA: 0.1})
	if s.Posture != PostureIsolate {
		t.Fatalf("got %d want isolate", s.Posture)
	}
}

func TestComputeFromJSON(t *testing.T) {
	s, err := ComputeFromJSON([]byte(`{"fault":true,"cause":"network","projected":0.25,"ewma":0.1,"mode":"semi","updated_at":"2026-08-24T00:00:00Z"}`))
	if err != nil {
		t.Fatal(err)
	}
	if s.Posture != PostureIsolate {
		t.Fatalf("got %d", s.Posture)
	}
}

func TestBEQuotaHint(t *testing.T) {
	if BEQuotaHint(PostureIsolate) != 10 {
		t.Fatal("isolate quota")
	}
	if BEQuotaHint(PostureObserve) != 50 {
		t.Fatal("observe quota")
	}
}

package forecaster

import (
	"testing"
	"time"
)

func TestMuEstimator(t *testing.T) {
	m := NewMuEstimator(1000)
	now := time.Now()
	v := m.Observe(XDPStats{Pass: 100}, 0.1, now)
	if v <= 0 {
		t.Fatalf("mu=%v", v)
	}
	now2 := now.Add(100 * time.Millisecond)
	v2 := m.Observe(XDPStats{Pass: 200}, 0.1, now2)
	if v2 <= 0 {
		t.Fatalf("mu2=%v", v2)
	}
}

func TestObserveLambda(t *testing.T) {
	te := NewTrafficEngine(DefaultTrafficConfig())
	now := time.Now()
	s1 := te.ObserveLambda(100, now)
	s2 := te.ObserveLambda(500, now.Add(time.Second))
	if s2.RhoProjected <= s1.RhoProjected && s2.LambdaEWMA < 100 {
		t.Fatalf("lambda track failed s1=%v s2=%v", s1, s2)
	}
}

func TestDecodeLambdaEvent(t *testing.T) {
	b := make([]byte, 32)
	_, err := decodeLambdaEvent(b)
	if err != nil {
		t.Fatal(err)
	}
}

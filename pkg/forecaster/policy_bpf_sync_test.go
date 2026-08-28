package forecaster

import (
	"os"
	"testing"
)

func TestEncodeBPFPolicyValue(t *testing.T) {
	snap := Snapshot{
		Fault:     true,
		Cause:     CauseNetwork,
		Projected: 0.5,
		EWMA:      0.1,
	}
	b := EncodeBPFPolicyValue(snap, 42)
	if len(b) != 32 {
		t.Fatalf("len=%d want 32", len(b))
	}
	if b[8] != 1 {
		t.Fatalf("fault byte=%d", b[8])
	}
	if b[9] != 1 {
		t.Fatalf("cause byte=%d", b[9])
	}
}

func TestSyncPolicyToBPFMapSkipsMissingPin(t *testing.T) {
	err := SyncPolicyToBPFMap("", Snapshot{})
	if err != nil {
		t.Fatal(err)
	}
	err = SyncPolicyToBPFMap("/nonexistent/path", Snapshot{})
	if err != nil {
		t.Fatal(err)
	}
}

func BenchmarkSyncPolicyToBPFMap(b *testing.B) {
	pin := os.Getenv("ELITE_POLICY_PIN")
	if pin == "" {
		b.Skip("ELITE_POLICY_PIN not set")
	}
	if _, err := os.Stat(pin); err != nil {
		b.Skip("pinned map missing")
	}
	snap := Snapshot{Fault: false, Cause: CauseNetwork, Projected: 0.05, EWMA: 0.01}
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		if err := SyncPolicyToBPFMap(pin, snap); err != nil {
			b.Fatal(err)
		}
	}
}

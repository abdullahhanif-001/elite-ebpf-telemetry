package forecaster

import (
	"os"
	"testing"
)

func TestPolicyABIByteLayout(t *testing.T) {
	snap := Snapshot{Fault: true, Cause: CauseNetwork, Projected: 0.25}
	b := EncodeBPFPolicyValue(snap, 3)
	if len(b) != 80 {
		t.Fatalf("ABI size=%d want 80", len(b))
	}
	if b[8] != 1 {
		t.Fatalf("fault at 8=%d", b[8])
	}
	if b[9] != 1 {
		t.Fatalf("cause at 9=%d want network=1", b[9])
	}
}

func TestSyncPolicyToBPFMapRoundTripWhenPinned(t *testing.T) {
	pin := os.Getenv("ELITE_POLICY_PIN")
	if pin == "" {
		t.Skip("ELITE_POLICY_PIN not set")
	}
	if _, err := os.Stat(pin); err != nil {
		t.Skip("pinned map missing")
	}
	snap := Snapshot{Fault: false, Cause: CauseNetwork, Projected: 0.1, EWMA: 0.05}
	if err := SyncPolicyToBPFMap(pin, snap, 1); err != nil {
		t.Fatal(err)
	}
}

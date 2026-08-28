package forecaster

import (
	"os"
	"path/filepath"
	"testing"
)

func TestWriteReadPolicyState(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "predict-policy.bin")
	snap := Snapshot{
		Fault:     true,
		Cause:     CauseNetwork,
		Projected: 0.12,
		EWMA:      0.08,
	}
	if err := WritePolicyState(path, snap); err != nil {
		t.Fatal(err)
	}
	got, err := ReadPolicyState(path)
	if err != nil {
		t.Fatal(err)
	}
	if !got.Fault || got.Cause != CauseNetwork {
		t.Fatalf("fault/cause: %+v", got)
	}
	if got.Projected < 0.119 || got.Projected > 0.121 {
		t.Fatalf("projected: %v", got.Projected)
	}
}

func TestWritePolicyStateCreatesDir(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "elite", "predict-policy.bin")
	if err := WritePolicyState(path, Snapshot{}); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(path); err != nil {
		t.Fatal(err)
	}
}

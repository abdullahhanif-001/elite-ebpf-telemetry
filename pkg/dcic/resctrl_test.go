package dcic

import "testing"

func TestShrinkCBM(t *testing.T) {
	if g := shrinkCBM("ff", 100); g != "ff" {
		t.Fatalf("full=%s", g)
	}
	g := shrinkCBM("ff", 50)
	// 8 bits -> keep 4 -> 0xf
	if g != "f" {
		t.Fatalf("half=%s want f", g)
	}
}

func TestResctrlAvailableFalseOnMissing(t *testing.T) {
	a := NewResctrlActuator("/tmp/elite-no-resctrl-xyz", nil)
	if a.Available() {
		t.Fatal("expected unavailable")
	}
}

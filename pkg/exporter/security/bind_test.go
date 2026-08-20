package security

import "testing"

func TestValidateListenAddressLoopback(t *testing.T) {
	if err := ValidateListenAddress("127.0.0.1:9102"); err != nil {
		t.Fatalf("loopback should be allowed: %v", err)
	}
}

func TestValidateListenAddressPublicRejected(t *testing.T) {
	t.Setenv("ELITE_ALLOW_PUBLIC_BIND", "")
	if err := ValidateListenAddress("0.0.0.0:9102"); err == nil {
		t.Fatal("expected public bind to be rejected")
	}
}

func TestValidateListenAddressPublicAllowed(t *testing.T) {
	t.Setenv("ELITE_ALLOW_PUBLIC_BIND", "1")
	if err := ValidateListenAddress("0.0.0.0:9102"); err != nil {
		t.Fatalf("ELITE_ALLOW_PUBLIC_BIND=1 should allow public bind: %v", err)
	}
}

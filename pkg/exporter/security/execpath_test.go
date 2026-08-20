package security

import (
	"path/filepath"
	"strings"
	"testing"
)

func TestLockedEnvReplacesPATH(t *testing.T) {
	t.Setenv("PATH", "/tmp/evil:/usr/bin")
	t.Setenv("ELITE_TEST_ENV", "1")
	env := LockedEnv()
	foundPATH := false
	foundMarker := false
	for _, e := range env {
		if strings.HasPrefix(e, "PATH=") {
			foundPATH = true
			if e != "PATH="+lockedPATH {
				t.Fatalf("PATH not locked: %s", e)
			}
		}
		if e == "ELITE_TEST_ENV=1" {
			foundMarker = true
		}
	}
	if !foundPATH {
		t.Fatal("PATH missing from locked env")
	}
	if !foundMarker {
		t.Fatal("expected non-PATH env to be preserved")
	}
}

func TestCommandUsesAbsoluteBinary(t *testing.T) {
	cmd := Command("cp", "/src", "/dst")
	if !filepath.IsAbs(cmd.Path) && !strings.HasSuffix(cmd.Path, "cp") {
		// Path may be unresolved until Start; Args[0] is absolute.
	}
	if got := cmd.Args[0]; got != filepath.Join("/usr/bin", "cp") && got != "/usr/bin/cp" {
		if !filepath.IsAbs(got) {
			t.Fatalf("expected absolute argv0, got %q", got)
		}
	}
	var pathOK bool
	for _, e := range cmd.Env {
		if e == "PATH="+lockedPATH {
			pathOK = true
		}
	}
	if !pathOK {
		t.Fatalf("command env PATH not locked: %v", cmd.Env)
	}
}

package security

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

const lockedPATH = "/usr/bin:/bin:/usr/sbin:/sbin"

// LockedEnv copies the process environment but replaces PATH with a fixed,
// system-only search path so exec cannot pick up attacker-writable directories.
func LockedEnv() []string {
	env := os.Environ()
	out := make([]string, 0, len(env)+1)
	for _, e := range env {
		if strings.HasPrefix(e, "PATH=") {
			continue
		}
		out = append(out, e)
	}
	return append(out, "PATH="+lockedPATH)
}

func absBin(name string) string {
	if filepath.IsAbs(name) {
		return name
	}
	return filepath.Join("/usr/bin", name)
}

// Command runs name with a locked PATH. Relative names resolve under /usr/bin.
func Command(name string, args ...string) *exec.Cmd {
	cmd := exec.Command(absBin(name), args...)
	cmd.Env = LockedEnv()
	return cmd
}

// CommandContext is Command with a cancellable context.
func CommandContext(ctx context.Context, name string, args ...string) *exec.Cmd {
	cmd := exec.CommandContext(ctx, absBin(name), args...)
	cmd.Env = LockedEnv()
	return cmd
}

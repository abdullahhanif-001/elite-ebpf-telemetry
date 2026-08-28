package main

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestLoadConfigDefaults(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "update.yaml")
	body := []byte("repo: abdullahhanif-001/elite-ebpf-telemetry\nauto_apply: true\ncheck_interval: 6h\n")
	if err := os.WriteFile(path, body, 0o644); err != nil {
		t.Fatal(err)
	}
	cfg, err := loadConfig(path)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Repo != "abdullahhanif-001/elite-ebpf-telemetry" {
		t.Fatalf("repo=%s", cfg.Repo)
	}
	if !cfg.AutoApply {
		t.Fatal("auto_apply")
	}
	if cfg.HealthTimeout != 45*time.Second {
		t.Fatalf("health_timeout=%s", cfg.HealthTimeout)
	}
	if cfg.BinDir != "/opt/elite/bin" {
		t.Fatalf("bin_dir=%s", cfg.BinDir)
	}
}

func TestVerifySHA256(t *testing.T) {
	dir := t.TempDir()
	bin := filepath.Join(dir, "elite-agent")
	if err := os.WriteFile(bin, []byte("hello-elite"), 0o755); err != nil {
		t.Fatal(err)
	}
	h := fileSHA(bin)
	sums := filepath.Join(dir, "SHA256SUMS")
	if err := os.WriteFile(sums, []byte(h+"  elite-agent\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := verifySHA256(sums, "elite-agent", bin); err != nil {
		t.Fatal(err)
	}
}

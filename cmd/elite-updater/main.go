// Command elite-updater checks GitHub Releases, verifies SHA256 (and optional
// cosign), atomically replaces elite-agent, health-checks, and rolls back on failure.
package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"time"

	"github.com/alibaba/kubeskoop/pkg/exporter/security"
	"gopkg.in/yaml.v3"
)

const (
	binEliteAgent   = "elite-agent"
	binEliteUpdater = "elite-updater"
	// Owner+group execute only — avoids world-executable binary modes (go:S2612).
	fileModeExe = 0o750
)

type config struct {
	Channel          string        `yaml:"channel"`
	Repo             string        `yaml:"repo"`
	CheckInterval    time.Duration `yaml:"check_interval"`
	AutoApply        bool          `yaml:"auto_apply"`
	BinDir           string        `yaml:"bin_dir"`
	PreviousDir      string        `yaml:"previous_dir"`
	AgentUnit        string        `yaml:"agent_unit"`
	AgentBin         string        `yaml:"agent_bin"`
	UpdaterBin       string        `yaml:"updater_bin"`
	HealthURL        string        `yaml:"health_url"`
	HealthTimeout    time.Duration `yaml:"health_timeout"`
	RequireCosign    bool          `yaml:"require_cosign"`
	AssetName        string        `yaml:"asset_name"`
	UpdatePacks      bool          `yaml:"update_packs"`
	VersionsEnvPath  string        `yaml:"versions_env_path"`
	PM2Guard         string        `yaml:"pm2_guard"`
	Once             bool          `yaml:"-"`
}

type ghRelease struct {
	TagName string `json:"tag_name"`
	Assets  []struct {
		Name               string `json:"name"`
		BrowserDownloadURL string `json:"browser_download_url"`
	} `json:"assets"`
}

func main() {
	cfgPath := flag.String("c", "/opt/elite/config/update.yaml", "update config")
	once := flag.Bool("once", true, "run one check and exit (systemd oneshot)")
	dryRun := flag.Bool("dry-run", false, "print planned actions only")
	flag.Parse()

	cfg, err := loadConfig(*cfgPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "elite-updater: config: %v\n", err)
		os.Exit(1)
	}
	cfg.Once = *once

	if err := run(context.Background(), cfg, *dryRun); err != nil {
		fmt.Fprintf(os.Stderr, "elite-updater: %v\n", err)
		os.Exit(1)
	}
}

func loadConfig(path string) (*config, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	c := &config{
		Channel:       "stable",
		Repo:          "abdullahhanif-001/elite-ebpf-telemetry",
		AutoApply:     true,
		BinDir:        "/opt/elite/bin",
		PreviousDir:   "/opt/elite/bin/previous",
		AgentUnit:     "elite-agent",
		AgentBin:      binEliteAgent,
		UpdaterBin:    binEliteUpdater,
		HealthURL:     "http://127.0.0.1:9102/metrics",
		HealthTimeout: 45 * time.Second,
		UpdatePacks:   true,
		PM2Guard:      "/opt/elite/scripts/pm2-guard.sh",
	}
	if err := yaml.Unmarshal(b, c); err != nil {
		return nil, err
	}
	if c.HealthTimeout <= 0 {
		c.HealthTimeout = 45 * time.Second
	}
	return c, nil
}

func run(ctx context.Context, cfg *config, dryRun bool) error {
	rel, err := fetchLatestRelease(ctx, cfg.Repo)
	if err != nil {
		return err
	}
	cur := currentVersion(filepath.Join(cfg.BinDir, cfg.AgentBin))
	fmt.Fprintf(os.Stderr, "elite-updater: current=%s latest=%s\n", cur, rel.TagName)
	if cur != "" && (cur == rel.TagName || strings.HasPrefix(cur, rel.TagName)) {
		fmt.Fprintln(os.Stderr, "elite-updater: already up to date")
		return nil
	}
	if !cfg.AutoApply {
		fmt.Fprintln(os.Stderr, "elite-updater: auto_apply=false; skipping")
		return nil
	}

	arch := runtime.GOARCH
	candidates := []string{
		cfg.AssetName,
		fmt.Sprintf("%s.linux-%s", binEliteAgent, arch),
		binEliteAgent,
	}
	assetURL, assetName := "", ""
	for _, name := range candidates {
		if name == "" {
			continue
		}
		for _, a := range rel.Assets {
			if a.Name == name {
				assetURL, assetName = a.BrowserDownloadURL, a.Name
				break
			}
		}
		if assetURL != "" {
			break
		}
	}
	if assetURL == "" {
		return fmt.Errorf("no elite-agent asset in release %s", rel.TagName)
	}

	sumsURL := ""
	for _, a := range rel.Assets {
		if a.Name == "SHA256SUMS" {
			sumsURL = a.BrowserDownloadURL
			break
		}
	}

	tmpDir, err := os.MkdirTemp("", "elite-updater-*")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmpDir)

	binPath := filepath.Join(tmpDir, assetName)
	if dryRun {
		fmt.Fprintf(os.Stderr, "DRY-RUN: download %s -> replace %s\n", assetURL, filepath.Join(cfg.BinDir, cfg.AgentBin))
		return nil
	}
	if err := downloadFile(ctx, assetURL, binPath); err != nil {
		return err
	}
	if sumsURL != "" {
		sumsPath := filepath.Join(tmpDir, "SHA256SUMS")
		if err := downloadFile(ctx, sumsURL, sumsPath); err != nil {
			return fmt.Errorf("SHA256SUMS: %w", err)
		}
		if err := verifySHA256(sumsPath, assetName, binPath); err != nil {
			return err
		}
		fmt.Fprintln(os.Stderr, "elite-updater: SHA256 OK")
	} else if cfg.RequireCosign {
		return fmt.Errorf("SHA256SUMS missing and require_cosign set")
	}

	if cfg.RequireCosign {
		if err := cosignVerify(ctx, binPath, assetURL+".sig"); err != nil {
			return fmt.Errorf("cosign: %w", err)
		}
	} else if cosignPath() != "" {
		sigURL := assetURL + ".sig"
		sigPath := binPath + ".sig"
		if err := downloadFile(ctx, sigURL, sigPath); err == nil {
			if err := cosignVerify(ctx, binPath, sigPath); err != nil {
				fmt.Fprintf(os.Stderr, "elite-updater: cosign warn: %v\n", err)
			} else {
				fmt.Fprintln(os.Stderr, "elite-updater: cosign OK")
			}
		}
	}

	dst := filepath.Join(cfg.BinDir, cfg.AgentBin)
	if err := atomicSwap(cfg, dst, binPath); err != nil {
		return err
	}

	_ = systemctl(ctx, "restart", cfg.AgentUnit)
	if err := waitHealthy(ctx, cfg.HealthURL, cfg.HealthTimeout); err != nil {
		fmt.Fprintf(os.Stderr, "elite-updater: health failed, rolling back: %v\n", err)
		if rb := rollback(cfg, dst); rb != nil {
			return fmt.Errorf("health failed (%v); rollback failed: %w", err, rb)
		}
		_ = systemctl(ctx, "restart", cfg.AgentUnit)
		return fmt.Errorf("health failed after update; rolled back: %w", err)
	}

	if cfg.PM2Guard != "" {
		if st, err := os.Stat(cfg.PM2Guard); err == nil && !st.IsDir() {
			cmd := security.CommandContext(ctx, "bash", cfg.PM2Guard)
			cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr
			if err := cmd.Run(); err != nil {
				fmt.Fprintf(os.Stderr, "elite-updater: pm2-guard warn: %v\n", err)
			}
		}
	}

	if cfg.UpdatePacks {
		if err := refreshVersionsEnv(ctx, cfg, rel); err != nil {
			fmt.Fprintf(os.Stderr, "elite-updater: versions.env warn: %v\n", err)
		}
	}

	fmt.Fprintf(os.Stderr, "elite-updater: applied %s OK\n", rel.TagName)
	return nil
}

func fetchLatestRelease(ctx context.Context, repo string) (*ghRelease, error) {
	url := fmt.Sprintf("https://api.github.com/repos/%s/releases/latest", repo)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("User-Agent", binEliteUpdater)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
		return nil, fmt.Errorf("github releases: %s: %s", resp.Status, string(b))
	}
	var rel ghRelease
	if err := json.NewDecoder(resp.Body).Decode(&rel); err != nil {
		return nil, err
	}
	if rel.TagName == "" {
		return nil, fmt.Errorf("empty release tag")
	}
	return &rel, nil
}

func currentVersion(bin string) string {
	cmd := security.Command(bin, "version")
	out, err := cmd.CombinedOutput()
	if err != nil {
		// try --version style or ldflags empty
		return strings.TrimSpace(readVersionFile())
	}
	s := strings.TrimSpace(string(out))
	// "KubeSkoop version: v1.2.3, Git sha: ..."
	if i := strings.Index(s, "version:"); i >= 0 {
		rest := strings.TrimSpace(s[i+len("version:"):])
		if j := strings.IndexByte(rest, ','); j >= 0 {
			return strings.TrimSpace(rest[:j])
		}
		return rest
	}
	return s
}

func readVersionFile() string {
	b, err := os.ReadFile("/opt/elite/bin/.installed-version")
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(b))
}

func downloadFile(ctx context.Context, url, dest string) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return err
	}
	req.Header.Set("User-Agent", binEliteUpdater)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return fmt.Errorf("download %s: %s", url, resp.Status)
	}
	f, err := os.OpenFile(dest, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, fileModeExe)
	if err != nil {
		return err
	}
	defer f.Close()
	_, err = io.Copy(f, resp.Body)
	return err
}

func verifySHA256(sumsPath, assetName, binPath string) error {
	b, err := os.ReadFile(sumsPath)
	if err != nil {
		return err
	}
	want := ""
	for _, line := range strings.Split(string(b), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) < 2 {
			continue
		}
		name := strings.TrimPrefix(fields[len(fields)-1], "./")
		if name == assetName {
			want = fields[0]
			break
		}
	}
	if want == "" {
		return fmt.Errorf("asset %s not listed in SHA256SUMS", assetName)
	}
	f, err := os.Open(binPath)
	if err != nil {
		return err
	}
	defer f.Close()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return err
	}
	got := hex.EncodeToString(h.Sum(nil))
	if !strings.EqualFold(got, want) {
		return fmt.Errorf("sha256 mismatch: got %s want %s", got, want)
	}
	return nil
}

func cosignPath() string {
	for _, p := range []string{"/usr/local/bin/cosign", "/usr/bin/cosign"} {
		st, err := os.Stat(p)
		if err == nil && !st.IsDir() {
			return p
		}
	}
	return ""
}

func cosignVerify(ctx context.Context, binPath, sigPath string) error {
	cosign := cosignPath()
	if cosign == "" {
		return fmt.Errorf("cosign binary not found under /usr/local/bin or /usr/bin")
	}
	cmd := security.CommandContext(ctx, cosign, "verify-blob",
		"--bundle", sigPath,
		"--certificate-identity-regexp", ".*",
		"--certificate-oidc-issuer-regexp", ".*",
		binPath,
	)
	out, err := cmd.CombinedOutput()
	if err == nil {
		return nil
	}
	cmd2 := security.CommandContext(ctx, cosign, "verify-blob",
		"--signature", sigPath,
		"--certificate-identity-regexp", ".*",
		"--certificate-oidc-issuer-regexp", ".*",
		binPath,
	)
	out2, err2 := cmd2.CombinedOutput()
	if err2 != nil {
		return fmt.Errorf("%v / %v: %s %s", err, err2, string(out), string(out2))
	}
	return nil
}

func atomicSwap(cfg *config, dst, src string) error {
	if err := os.MkdirAll(cfg.BinDir, 0o755); err != nil {
		return err
	}
	if err := os.MkdirAll(cfg.PreviousDir, 0o755); err != nil {
		return err
	}
	prev := filepath.Join(cfg.PreviousDir, cfg.AgentBin)
	if _, err := os.Stat(dst); err == nil {
		_ = os.Remove(prev)
		if err := os.Rename(dst, prev); err != nil {
			// cross-device: copy
			if err2 := copyFile(dst, prev); err2 != nil {
				return err
			}
			_ = os.Remove(dst)
		}
	}
	if err := copyFile(src, dst); err != nil {
		return err
	}
	return os.Chmod(dst, fileModeExe)
}

func rollback(cfg *config, dst string) error {
	prev := filepath.Join(cfg.PreviousDir, cfg.AgentBin)
	if _, err := os.Stat(prev); err != nil {
		return fmt.Errorf("no previous binary at %s", prev)
	}
	_ = os.Remove(dst)
	return copyFile(prev, dst)
}

func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.OpenFile(dst, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, fileModeExe)
	if err != nil {
		return err
	}
	defer out.Close()
	_, err = io.Copy(out, in)
	return err
}

func systemctl(ctx context.Context, args ...string) error {
	cmd := security.CommandContext(ctx, "systemctl", args...)
	cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr
	return cmd.Run()
}

func waitHealthy(ctx context.Context, url string, timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	client := &http.Client{Timeout: 5 * time.Second}
	for time.Now().Before(deadline) {
		req, _ := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
		resp, err := client.Do(req)
		if err == nil {
			body, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
			resp.Body.Close()
			if resp.StatusCode == 200 && strings.Contains(string(body), "elite_") {
				return nil
			}
		}
		time.Sleep(2 * time.Second)
	}
	return fmt.Errorf("timeout waiting for %s", url)
}

func refreshVersionsEnv(ctx context.Context, cfg *config, rel *ghRelease) error {
	url := ""
	for _, a := range rel.Assets {
		if a.Name == "versions.env" {
			url = a.BrowserDownloadURL
			break
		}
	}
	if url == "" || cfg.VersionsEnvPath == "" {
		return nil
	}
	tmp := cfg.VersionsEnvPath + ".new"
	if err := downloadFile(ctx, url, tmp); err != nil {
		return err
	}
	oldHash := fileSHA(cfg.VersionsEnvPath)
	newHash := fileSHA(tmp)
	if oldHash != "" && oldHash == newHash {
		_ = os.Remove(tmp)
		return nil
	}
	if err := os.MkdirAll(filepath.Dir(cfg.VersionsEnvPath), 0o755); err != nil {
		return err
	}
	if err := os.Rename(tmp, cfg.VersionsEnvPath); err != nil {
		return err
	}
	fmt.Fprintln(os.Stderr, "elite-updater: versions.env refreshed (re-run elite-oneclick packs if pins changed)")
	return nil
}

func fileSHA(path string) string {
	f, err := os.Open(path)
	if err != nil {
		return ""
	}
	defer f.Close()
	h := sha256.New()
	_, _ = io.Copy(h, f)
	return hex.EncodeToString(h.Sum(nil))
}

// Command elite-dcic runs Soft Track A DCIC control on Linux VPS hosts.
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"math"
	"net/http"
	"os"
	"os/signal"
	"runtime"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/alibaba/kubeskoop/pkg/dcic"
	"github.com/alibaba/kubeskoop/pkg/forecaster"
)

func main() {
	mode := flag.String("mode", "observe", "observe|advise|enforce")
	interval := flag.Duration("interval", time.Second, "control epoch")
	listen := flag.String("listen", "127.0.0.1:9103", "metrics listen")
	hardDrop := flag.Float64("hard-drop", 0.05, "LC latency seconds trip threshold")
	lcCpus := flag.String("lc-cpus", "0-1", "LC cpuset")
	beCpus := flag.String("be-cpus", "2-3", "BE cpuset")
	cgroupRoot := flag.String("cgroup-root", "/sys/fs/cgroup/elite-dcic", "cgroup root")
	capPath := flag.String("capability", "/etc/elite/dcic-capability.json", "capability gate JSON")
	decisionPath := flag.String("decision", "/var/lib/elite/predict-decision.json", "forecaster decision bus")
	policyPath := flag.String("policy", "/var/lib/elite/predict-policy.bin", "forecaster binary policy")
	actuateTrack := flag.String("actuate-track", "auto", "soft|hard|auto")
	flag.Parse()

	track := dcic.TrackSoft
	trackBOK := false
	if b, err := os.ReadFile(*capPath); err == nil {
		var cap map[string]any
		if json.Unmarshal(b, &cap) == nil {
			if t, ok := cap["track"].(string); ok && t != "" {
				track = t
			}
			if v, ok := cap["track_b_ok"].(bool); ok {
				trackBOK = v
			}
		}
	}
	useHard := *actuateTrack == "hard" || (*actuateTrack == "auto" && trackBOK && track == dcic.TrackHard)
	if useHard {
		track = dcic.TrackHard
	} else {
		track = dcic.TrackSoft
	}

	cfg := dcic.DefaultConfig()
	cfg.Mode = *mode
	cfg.Track = track
	cfg.Interval = *interval
	cfg.MetricsAddr = *listen
	cfg.HardDrop = *hardDrop
	cfg.LCCpus = *lcCpus
	cfg.BECpus = *beCpus
	cfg.CgroupRoot = *cgroupRoot

	ctrl := dcic.NewController(cfg)
	cg := dcic.NewCgroupActuator(cfg.CgroupRoot)
	var act dcic.Actuator = cg
	if useHard {
		act = dcic.NewResctrlActuator("/sys/fs/resctrl", cg)
	}
	if cfg.Mode == dcic.ModeEnforce {
		if err := act.EnsureHierarchy(cfg.LCCpus, cfg.BECpus); err != nil {
			fmt.Fprintf(os.Stderr, "hierarchy: %v (continuing)\n", err)
		}
		_ = act.SetBEQuotaPercent(cfg.BEQuotaPct)
	}

	var lcLatencyNs atomic.Uint64

	mux := http.NewServeMux()
	mux.HandleFunc("/metrics", func(w http.ResponseWriter, r *http.Request) {
		s := ctrl.Snapshot()
		lat := float64(lcLatencyNs.Load()) / 1e9
		fmt.Fprintf(w, "# HELP elite_dcic_noise_score Soft DCIC noise score (EWMA latency).\n")
		fmt.Fprintf(w, "# TYPE elite_dcic_noise_score gauge\n")
		fmt.Fprintf(w, "elite_dcic_noise_score %.6f\n", s.NoiseEWMA)
		fmt.Fprintf(w, "# HELP elite_dcic_lc_latency_seconds LC probe latency.\n")
		fmt.Fprintf(w, "# TYPE elite_dcic_lc_latency_seconds gauge\n")
		fmt.Fprintf(w, "elite_dcic_lc_latency_seconds %.9f\n", lat)
		fmt.Fprintf(w, "# HELP elite_dcic_be_quota_percent BE cgroup CPU quota percent.\n")
		fmt.Fprintf(w, "# TYPE elite_dcic_be_quota_percent gauge\n")
		fmt.Fprintf(w, "elite_dcic_be_quota_percent %d\n", s.BEQuotaPct)
		fmt.Fprintf(w, "# HELP elite_dcic_fault Soft DCIC fault trip.\n")
		fmt.Fprintf(w, "# TYPE elite_dcic_fault gauge\n")
		fault := 0
		if s.Fault {
			fault = 1
		}
		fmt.Fprintf(w, "elite_dcic_fault %d\n", fault)
		fmt.Fprintf(w, "# HELP elite_dcic_pressure_cpu CPU PSI avg10.\n")
		fmt.Fprintf(w, "# TYPE elite_dcic_pressure_cpu gauge\n")
		fmt.Fprintf(w, "elite_dcic_pressure_cpu %.4f\n", s.Pressure)
		fmt.Fprintf(w, "# HELP elite_dcic_samples_total Control samples.\n")
		fmt.Fprintf(w, "# TYPE elite_dcic_samples_total counter\n")
		fmt.Fprintf(w, "elite_dcic_samples_total %d\n", s.Samples)
		fmt.Fprintf(w, "# HELP elite_socketlatency_dcic_seconds Alias for Soft Track A LC probe.\n")
		fmt.Fprintf(w, "# TYPE elite_socketlatency_dcic_seconds gauge\n")
		fmt.Fprintf(w, "elite_socketlatency_dcic_seconds %.9f\n", lat)
		fmt.Fprintf(w, "# HELP elite_dcic_track Track encoding (1=soft 2=hard).\n")
		fmt.Fprintf(w, "# TYPE elite_dcic_track gauge\n")
		tr := 1
		if s.Track == dcic.TrackHard {
			tr = 2
		}
		fmt.Fprintf(w, "elite_dcic_track %d\n", tr)
	})
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(200)
		_, _ = w.Write([]byte("ok\n"))
	})

	srv := &http.Server{Addr: cfg.MetricsAddr, Handler: mux}
	go func() {
		fmt.Printf("elite-dcic mode=%s track=%s listen=%s\n", cfg.Mode, cfg.Track, cfg.MetricsAddr)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			fmt.Fprintf(os.Stderr, "metrics: %v\n", err)
			os.Exit(1)
		}
	}()

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	// LC latency probe: touch a small working set (guest L2-sized).
	go runLCProbe(ctx, &lcLatencyNs)

	t := time.NewTicker(cfg.Interval)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			_ = act.Reset()
			shutdownCtx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
			_ = srv.Shutdown(shutdownCtx)
			cancel()
			return
		case now := <-t.C:
			lat := float64(lcLatencyNs.Load()) / 1e9
			pressure := dcic.ReadCPUPressure()
			noise := lat
			if pressure/100.0 > noise {
				noise = math.Max(noise, pressure/1000.0)
			}
			// Shared decision bus from forecaster (ADR-004) — policy bin first, JSON fallback.
			if snap, err := forecaster.ReadPolicyState(*policyPath); err == nil && snap.Fault {
				if snap.Projected > noise {
					noise = snap.Projected
				} else {
					noise = math.Max(noise, cfg.HardDrop)
				}
			} else if b, err := os.ReadFile(*decisionPath); err == nil {
				var d struct {
					Fault     bool    `json:"fault"`
					Projected float64 `json:"projected"`
				}
				if json.Unmarshal(b, &d) == nil && d.Fault {
					if d.Projected > noise {
						noise = d.Projected
					} else {
						noise = math.Max(noise, cfg.HardDrop)
					}
				}
			}
			dec := ctrl.Observe(noise, pressure, now)
			if cfg.Mode == dcic.ModeEnforce && (dec.Action == "shrink_be" || dec.Action == "reclaim_be") {
				if err := act.SetBEQuotaPercent(dec.BEQuotaPct); err != nil {
					fmt.Fprintf(os.Stderr, "actuate: %v\n", err)
				} else {
					fmt.Printf("actuate %s be_quota=%d%% reason=%s track=%s\n", dec.Action, dec.BEQuotaPct, dec.Reason, cfg.Track)
				}
			} else if dec.Action != "none" {
				fmt.Printf("decision %s be_quota=%d%% reason=%s\n", dec.Action, dec.BEQuotaPct, dec.Reason)
			}
		}
	}
}

func runLCProbe(ctx context.Context, out *atomic.Uint64) {
	const size = 2 << 20 // 2 MiB — fits guest L2 pressure scenarios
	buf := make([]byte, size)
	for i := range buf {
		buf[i] = byte(i)
	}
	runtime.KeepAlive(buf)
	idx := 0
	for {
		select {
		case <-ctx.Done():
			return
		default:
			start := time.Now()
			var sum byte
			for i := 0; i < 4096; i++ {
				idx = (idx + 64) % size
				sum ^= buf[idx]
			}
			runtime.KeepAlive(sum)
			out.Store(uint64(time.Since(start)))
			time.Sleep(50 * time.Millisecond)
		}
	}
}

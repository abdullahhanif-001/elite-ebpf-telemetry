// Command elite-llc-sensors exposes elite_llc_* on localhost via periodic perf sampling.
// Falls back to llc_enabled=0 when perf/PMU unavailable (exit metrics still serve).
package main

import (
	"flag"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/alibaba/kubeskoop/pkg/llc"
)

func main() {
	listen := flag.String("listen", "127.0.0.1:9104", "metrics listen address")
	interval := flag.Duration("interval", time.Second, "sample interval")
	samplePeriod := flag.Int("sample-period", 10000, "perf sample period hint")
	mode := flag.String("llc", "auto", "auto|on|off")
	flag.Parse()

	s := llc.NewSampler()
	enabled := *mode == "on" || (*mode == "auto" && s.Detect())
	if *mode == "off" {
		enabled = false
		s.SetEnabled(false, "forced_off")
	}
	if !enabled && *mode == "auto" {
		s.SetEnabled(false, s.Snapshot().LastError)
	}

	var mu sync.Mutex
	go func() {
		if !enabled {
			return
		}
		ticker := time.NewTicker(*interval)
		defer ticker.Stop()
		for now := range ticker.C {
			refs, misses, ok := samplePerf(*samplePeriod)
			mu.Lock()
			if !ok {
				s.SetEnabled(false, "perf_unavailable")
			} else {
				s.SetEnabled(true, "")
				s.ObserveRaw(refs, misses, now)
			}
			mu.Unlock()
		}
	}()

	mux := http.NewServeMux()
	mux.HandleFunc("/metrics", func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		sn := s.Snapshot()
		mu.Unlock()
		w.Header().Set("Content-Type", "text/plain; version=0.0.4")
		_, _ = w.Write([]byte(llc.FormatPrometheus(sn)))
	})
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(200)
		_, _ = w.Write([]byte("ok\n"))
	})

	fmt.Fprintf(os.Stderr, "elite-llc-sensors listen=%s llc_enabled=%v\n", *listen, enabled)
	if err := http.ListenAndServe(*listen, mux); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func samplePerf(period int) (refs, misses uint64, ok bool) {
	// Short sleep window with perf stat -a (system-wide). Requires CAP_PERFMON/root.
	_ = period
	perfBin := "/usr/bin/perf"
	if _, err := os.Stat(perfBin); err != nil {
		perfBin = "/bin/perf"
	}
	cmd := exec.Command(perfBin, "stat", "-a", "-e", "cache-references,cache-misses", "--", "/bin/sleep", "0.2")
	cmd.Env = []string{"PATH=/usr/bin:/bin", "LANG=C"}
	out, err := cmd.CombinedOutput()
	if err != nil {
		return 0, 0, false
	}
	for _, line := range strings.Split(string(out), "\n") {
		line = strings.TrimSpace(line)
		fields := strings.Fields(line)
		if len(fields) < 2 {
			continue
		}
		num := strings.ReplaceAll(fields[0], ",", "")
		v, perr := strconv.ParseUint(num, 10, 64)
		if perr != nil {
			continue
		}
		rest := strings.Join(fields[1:], " ")
		if strings.Contains(rest, "cache-references") {
			refs = v
			ok = true
		}
		if strings.Contains(rest, "cache-misses") {
			misses = v
			ok = true
		}
	}
	return refs, misses, ok
}

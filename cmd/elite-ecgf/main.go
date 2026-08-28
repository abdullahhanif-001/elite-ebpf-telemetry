// Command elite-ecgf runs ECGF-lite posture control (ADR-005). No novel BPF.
package main

import (
	"context"
	"flag"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"sync"
	"syscall"
	"time"

	"github.com/alibaba/kubeskoop/pkg/ecgf"
)

func main() {
	listen := flag.String("listen", "127.0.0.1:9105", "metrics listen")
	decision := flag.String("decision", "/var/lib/elite/predict-decision.json", "decision bus path")
	statePath := flag.String("state", "/var/lib/elite/ecgf/posture.json", "posture state path")
	hintPath := flag.String("be-hint", "/var/lib/elite/ecgf/be-quota.hint", "Soft DCIC BE quota hint")
	interval := flag.Duration("interval", time.Second, "control loop")
	flag.Parse()

	_ = os.MkdirAll(filepath.Dir(*statePath), 0o755)

	var mu sync.Mutex
	cur := ecgf.State{Posture: ecgf.PostureObserve, Label: "observe", UpdatedAt: time.Now().UTC(), Source: "boot"}

	mux := http.NewServeMux()
	mux.HandleFunc("/metrics", func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		s := cur
		mu.Unlock()
		w.Header().Set("Content-Type", "text/plain; version=0.0.4")
		fmt.Fprintf(w, "# HELP elite_ecgf_posture ECGF posture 0=observe 1=tighten 2=isolate.\n")
		fmt.Fprintf(w, "# TYPE elite_ecgf_posture gauge\n")
		fmt.Fprintf(w, "elite_ecgf_posture %d\n", s.Posture)
		fmt.Fprintf(w, "# HELP elite_ecgf_fault Decision bus fault flag.\n")
		fmt.Fprintf(w, "# TYPE elite_ecgf_fault gauge\n")
		f := 0
		if s.Fault {
			f = 1
		}
		fmt.Fprintf(w, "elite_ecgf_fault %d\n", f)
		fmt.Fprintf(w, "# HELP elite_ecgf_be_quota_hint Suggested BE CPU quota percent.\n")
		fmt.Fprintf(w, "# TYPE elite_ecgf_be_quota_hint gauge\n")
		fmt.Fprintf(w, "elite_ecgf_be_quota_hint %d\n", ecgf.BEQuotaHint(s.Posture))
	})
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(200)
		_, _ = w.Write([]byte("ok\n"))
	})

	srv := &http.Server{Addr: *listen, Handler: mux}
	go func() {
		fmt.Fprintf(os.Stderr, "elite-ecgf listen=%s decision=%s\n", *listen, *decision)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
	}()

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	tick := time.NewTicker(*interval)
	defer tick.Stop()
	for {
		select {
		case <-ctx.Done():
			_ = srv.Shutdown(context.Background())
			return
		case <-tick.C:
			s := ecgf.State{Posture: ecgf.PostureObserve, Label: "observe", UpdatedAt: time.Now().UTC(), Source: "missing_bus"}
			if b, err := os.ReadFile(*decision); err == nil {
				if st, err2 := ecgf.ComputeFromJSON(b); err2 == nil {
					s = st
				} else {
					s.Source = "parse_error"
				}
			}
			_ = ecgf.WriteState(*statePath, s)
			_ = os.WriteFile(*hintPath, []byte(fmt.Sprintf("%d\n", ecgf.BEQuotaHint(s.Posture))), 0o640)
			mu.Lock()
			cur = s
			mu.Unlock()
		}
	}
}

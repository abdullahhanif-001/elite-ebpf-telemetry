package cmd

import (
	"fmt"
	"os"
	"runtime"
	"time"

	"github.com/spf13/cobra"
)

var benchCmd = &cobra.Command{
	Use:   "bench",
	Short: "Print elite-agent self overhead snapshot (run on node)",
	Run: func(_ *cobra.Command, args []string) {
		duration := 10 * time.Second
		if len(args) > 0 {
			if d, err := time.ParseDuration(args[0]); err == nil {
				duration = d
			}
		}

		var m0, m1 runtime.MemStats
		runtime.ReadMemStats(&m0)
		start := time.Now()
		for time.Since(start) < duration {
			runtime.Gosched()
		}
		runtime.ReadMemStats(&m1)

		allocMB := float64(m1.Alloc-m0.Alloc) / 1024 / 1024
		fmt.Fprintf(os.Stdout, "elite_bench duration=%s goroutines=%d alloc_delta_mb=%.2f\n",
			duration, runtime.NumGoroutine(), allocMB)
		fmt.Fprintf(os.Stdout, "target: agent_cpu_overhead < 1%% @ 10k RPS (see benchmarks/run-overhead.sh)\n")
	},
}

func init() {
	rootCmd.AddCommand(benchCmd)
}

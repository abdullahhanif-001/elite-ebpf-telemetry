// Package llc samples Last-Level Cache references/misses via Linux perf
// (PERF_COUNT_HW_CACHE_*) and exposes Prometheus text for the closed loop.
// On VMs without PMU access, Enabled stays false and metrics report llc_enabled=0.
package llc

import (
	"bufio"
	"fmt"
	"os"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"time"
)

// Snapshot is a lock-free readable LLC sample.
type Snapshot struct {
	Enabled    bool
	Refs       uint64
	Misses     uint64
	HitRatio   float64
	MissRate   float64 // misses per second (approx)
	Samples    int
	LastError  string
}

// Sampler polls /proc/perf or falls back to reading cumulative counters
// exposed by a companion helper. Pure-Go path uses sysfs/perf_event when
// opened by the sensors binary; this package holds math + scrape text.
type Sampler struct {
	mu       sync.Mutex
	enabled  bool
	refs     uint64
	misses   uint64
	prevRefs uint64
	prevMiss uint64
	prevAt   time.Time
	missRate float64
	samples  int
	lastErr  string
	snap     Snapshot
}

// NewSampler builds a sampler; call Detect() then Observe deltas.
func NewSampler() *Sampler {
	return &Sampler{}
}

// Detect checks whether LLC sampling is plausible on this host.
func (s *Sampler) Detect() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	if runtime.GOOS != "linux" {
		s.enabled = false
		s.lastErr = "not_linux"
		s.snap = Snapshot{Enabled: false, LastError: s.lastErr}
		return false
	}
	// Hypervisor guests often lack PMU — still allow explicit enable.
	b, err := os.ReadFile("/proc/cpuinfo")
	if err != nil {
		s.enabled = false
		s.lastErr = "no_cpuinfo"
		s.snap = Snapshot{Enabled: false, LastError: s.lastErr}
		return false
	}
	txt := string(b)
	if strings.Contains(txt, "hypervisor") {
		// Soft detect: may still work on some Server SKUs.
		s.lastErr = "hypervisor_pmu_uncertain"
	}
	s.enabled = true
	s.snap = Snapshot{Enabled: true, LastError: s.lastErr}
	return true
}

// ObserveRaw ingests absolute ref/miss counters (from perf_event reads).
func (s *Sampler) ObserveRaw(refs, misses uint64, now time.Time) Snapshot {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.samples++
	if !s.prevAt.IsZero() {
		dt := now.Sub(s.prevAt).Seconds()
		if dt > 0 && refs >= s.prevRefs && misses >= s.prevMiss {
			dMiss := float64(misses - s.prevMiss)
			s.missRate = dMiss / dt
		}
	}
	s.prevRefs = refs
	s.prevMiss = misses
	s.prevAt = now
	s.refs = refs
	s.misses = misses
	hit := 0.0
	if refs > 0 {
		if misses > refs {
			misses = refs
		}
		hit = float64(refs-misses) / float64(refs)
	}
	s.snap = Snapshot{
		Enabled:   s.enabled,
		Refs:      refs,
		Misses:    misses,
		HitRatio:  hit,
		MissRate:  s.missRate,
		Samples:   s.samples,
		LastError: s.lastErr,
	}
	return s.snap
}

// SetEnabled forces enabled flag (e.g. after perf_event_open failure).
func (s *Sampler) SetEnabled(ok bool, reason string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.enabled = ok
	s.lastErr = reason
	s.snap.Enabled = ok
	s.snap.LastError = reason
}

// Snapshot returns the latest sample.
func (s *Sampler) Snapshot() Snapshot {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.snap
}

// HitRatio computes cache hit ratio from refs/misses.
func HitRatio(refs, misses uint64) float64 {
	if refs == 0 {
		return 0
	}
	if misses > refs {
		misses = refs
	}
	return float64(refs-misses) / float64(refs)
}

// FormatPrometheus writes elite_llc_* text exposition.
func FormatPrometheus(sn Snapshot) string {
	en := 0.0
	if sn.Enabled {
		en = 1
	}
	var b strings.Builder
	b.WriteString("# HELP elite_llc_enabled 1 if LLC PERF sampling is active.\n")
	b.WriteString("# TYPE elite_llc_enabled gauge\n")
	fmt.Fprintf(&b, "elite_llc_enabled %g\n", en)
	b.WriteString("# HELP elite_llc_references_total Cumulative cache references (sampled).\n")
	b.WriteString("# TYPE elite_llc_references_total counter\n")
	fmt.Fprintf(&b, "elite_llc_references_total %d\n", sn.Refs)
	b.WriteString("# HELP elite_llc_misses_total Cumulative cache misses (sampled).\n")
	b.WriteString("# TYPE elite_llc_misses_total counter\n")
	fmt.Fprintf(&b, "elite_llc_misses_total %d\n", sn.Misses)
	b.WriteString("# HELP elite_llc_hit_ratio Cache hit ratio (0-1).\n")
	b.WriteString("# TYPE elite_llc_hit_ratio gauge\n")
	fmt.Fprintf(&b, "elite_llc_hit_ratio %g\n", sn.HitRatio)
	b.WriteString("# HELP elite_llc_miss_rate Misses per second (approx).\n")
	b.WriteString("# TYPE elite_llc_miss_rate gauge\n")
	fmt.Fprintf(&b, "elite_llc_miss_rate %g\n", sn.MissRate)
	return b.String()
}

// ParsePerfStatLines parses `perf stat -e cache-references,cache-misses` summary lines.
func ParsePerfStatLines(r *bufio.Scanner) (refs, misses uint64, ok bool) {
	for r.Scan() {
		line := strings.TrimSpace(r.Text())
		fields := strings.Fields(line)
		if len(fields) < 2 {
			continue
		}
		num := strings.ReplaceAll(fields[0], ",", "")
		v, err := strconv.ParseUint(num, 10, 64)
		if err != nil {
			continue
		}
		joined := strings.Join(fields[1:], " ")
		if strings.Contains(joined, "cache-references") {
			refs = v
			ok = true
		}
		if strings.Contains(joined, "cache-misses") {
			misses = v
			ok = true
		}
	}
	return refs, misses, ok
}

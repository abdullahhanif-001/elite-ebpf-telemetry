package forecaster

import (
	"context"
	"sync"
	"sync/atomic"
	"time"

	log "github.com/sirupsen/logrus"
)

// ModeDryRun only logs + metrics. ModeSemi also sheds event probes temporarily.
const (
	ModeDryRun = "dry-run"
	ModeSemi   = "semi"
)

// EventShedder temporarily clears event probes (semi mode). Metrics stay up.
type EventShedder interface {
	ShedEvents(ctx context.Context) error
	RestoreEvents(ctx context.Context) error
}

// Config is the YAML-facing forecaster configuration (mapped from cmd package).
type Config struct {
	Enabled         bool
	Interval        time.Duration
	Horizon         time.Duration
	Window          int
	Alpha           float64
	HardDropSeconds float64
	AccThreshold    float64
	Mode            string
	Targets         []Target
	SemiCooldown    time.Duration
	LLCURL          string  // optional elite_llc metrics e.g. http://127.0.0.1:9104/metrics
	ReadPSI         bool    // read /proc/pressure/cpu
	DecisionPath    string  // shared decision bus for Soft DCIC
	PolicyPath      string  // binary hot path for elite-dcic
	PolicyMapPin    string  // pinned BPF map for XDP mitigator
	Weights         FuseWeights
}

// sampleSource abstracts scrape for tests.
type sampleSource interface {
	Sample(now time.Time) (float64, error)
}

// Runner owns scrape → engine → metrics → optional semi action.
type Runner struct {
	cfg     Config
	engine  *Engine
	scraper sampleSource
	snaps   [2]Snapshot
	idx     atomic.Uint32
	coll    *Collector
	shedder EventShedder

	mu           sync.Mutex
	shedding     bool
	restoreAfter time.Time
	prevFault    bool
}

// NewRunner builds a runner; returns nil collector if disabled.
func NewRunner(cfg Config, shedder EventShedder) (*Runner, *Collector) {
	if !cfg.Enabled {
		return nil, nil
	}
	if cfg.Interval <= 0 {
		cfg.Interval = time.Second
	}
	if cfg.Horizon <= 0 {
		cfg.Horizon = 5 * time.Second
	}
	if cfg.Window <= 0 {
		cfg.Window = 8
	}
	if cfg.Alpha <= 0 {
		cfg.Alpha = 0.3
	}
	if cfg.HardDropSeconds <= 0 {
		cfg.HardDropSeconds = 0.1
	}
	if cfg.AccThreshold <= 0 {
		cfg.AccThreshold = 0.001
	}
	if cfg.Mode != ModeSemi {
		cfg.Mode = ModeDryRun
	}
	if cfg.SemiCooldown <= 0 {
		cfg.SemiCooldown = 60 * time.Second
	}
	if len(cfg.Targets) == 0 {
		cfg.Targets = []Target{
			{URL: "http://127.0.0.1:9435/metrics", Series: []string{"softirq_wait_seconds"}},
			{URL: "http://127.0.0.1:9102/metrics", Series: []string{"elite_socketlatency"}},
		}
	}
	if cfg.Weights.Network == 0 && cfg.Weights.LLC == 0 && cfg.Weights.PSI == 0 {
		cfg.Weights = DefaultFuseWeights()
	}
	if cfg.DecisionPath == "" {
		cfg.DecisionPath = "/var/lib/elite/predict-decision.json"
	}

	r := &Runner{
		cfg: cfg,
		engine: NewEngine(EngineConfig{
			Alpha:          cfg.Alpha,
			Window:         cfg.Window,
			Horizon:        cfg.Horizon,
			HardDrop:       cfg.HardDropSeconds,
			AccThreshold:   cfg.AccThreshold,
			SampleInterval: cfg.Interval,
		}),
		scraper: NewScraper(cfg.Targets),
		shedder: shedder,
	}
	r.coll = NewCollector(&r.snaps, &r.idx, cfg.Mode)
	return r, r.coll
}

// Collector returns the prometheus collector (nil if disabled).
func (r *Runner) Collector() *Collector {
	if r == nil {
		return nil
	}
	return r.coll
}

// Run ticks until ctx is cancelled.
func (r *Runner) Run(ctx context.Context) {
	if r == nil {
		return
	}
	t := time.NewTicker(r.cfg.Interval)
	defer t.Stop()
	log.Infof("forecaster started mode=%s interval=%s horizon=%s hardDrop=%.3fs",
		r.cfg.Mode, r.cfg.Interval, r.cfg.Horizon, r.cfg.HardDropSeconds)

	for {
		select {
		case <-ctx.Done():
			log.Info("forecaster stopped")
			return
		case now := <-t.C:
			r.tick(ctx, now)
		}
	}
}

func (r *Runner) tick(ctx context.Context, now time.Time) {
	netRaw, err := r.scraper.Sample(now)
	if err != nil {
		log.Debugf("forecaster scrape: %v", err)
		// still try LLC/PSI for blame path
		netRaw = 0
	}
	vec := SignalVector{Network: netRaw}
	if r.cfg.LLCURL != "" {
		if mr, ok := scrapeLLCMissRate(r.cfg.LLCURL); ok {
			vec.HasLLC = true
			vec.LLC = MapLLCMissRate(mr, r.cfg.HardDropSeconds)
		}
	}
	if r.cfg.ReadPSI {
		if p, ok := readPSISomeAvg10(); ok {
			vec.HasPSI = true
			vec.PSI = MapPSI(p, r.cfg.HardDropSeconds)
		}
	}
	fused := FuseScalar(vec, r.cfg.Weights)
	cause := BlameCause(vec, r.cfg.HardDropSeconds)
	r.applySample(ctx, fused, cause, now)
}

func (r *Runner) applySample(ctx context.Context, raw float64, cause string, now time.Time) {
	snap := r.engine.Observe(raw, now)
	if snap.Fault {
		if cause == CauseNone {
			cause = CauseNetwork
		}
		snap.Cause = cause
	} else {
		snap.Cause = CauseNone
	}
	next := 1 - (r.idx.Load() % 2)
	r.snaps[next] = snap
	r.idx.Store(next)
	_ = WriteDecision(r.cfg.DecisionPath, snap)
	_ = WritePolicyState(r.cfg.PolicyPath, snap)
	_ = SyncPolicyToBPFMap(r.cfg.PolicyMapPin, snap)

	if snap.Fault && !r.prevFault {
		r.coll.IncFaults()
		log.Warnf("forecaster FAULT cause=%s projected=%.4fs ewma=%.4fs vel=%.4f acc=%.4f mode=%s",
			snap.Cause, snap.Projected, snap.EWMA, snap.Velocity, snap.Acceleration, r.cfg.Mode)
		if r.cfg.Mode == ModeSemi && r.shedder != nil && ShouldShedEvents(snap.Cause) {
			r.maybeShed(ctx, now)
		}
	}
	r.prevFault = snap.Fault

	r.mu.Lock()
	restoreDue := r.shedding && !r.restoreAfter.IsZero() && now.After(r.restoreAfter)
	r.mu.Unlock()
	if restoreDue {
		r.maybeRestore(ctx)
	}
}

func (r *Runner) maybeShed(ctx context.Context, now time.Time) {
	r.mu.Lock()
	if r.shedding {
		r.mu.Unlock()
		return
	}
	r.shedding = true
	r.restoreAfter = now.Add(r.cfg.SemiCooldown)
	r.mu.Unlock()

	if err := r.shedder.ShedEvents(ctx); err != nil {
		log.Warnf("forecaster semi shed events: %v", err)
		r.mu.Lock()
		r.shedding = false
		r.restoreAfter = time.Time{}
		r.mu.Unlock()
		return
	}
	log.Warnf("forecaster semi: event probes shed for %s", r.cfg.SemiCooldown)
}

func (r *Runner) maybeRestore(ctx context.Context) {
	r.mu.Lock()
	if !r.shedding {
		r.mu.Unlock()
		return
	}
	r.mu.Unlock()
	if err := r.shedder.RestoreEvents(ctx); err != nil {
		log.Warnf("forecaster semi restore events: %v", err)
		return
	}
	r.mu.Lock()
	r.shedding = false
	r.restoreAfter = time.Time{}
	r.mu.Unlock()
	log.Infof("forecaster semi: event probes restored")
}

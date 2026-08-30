package forecaster

import (
	"context"
	"fmt"
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
	LLCURL          string
	ReadPSI         bool
	DecisionPath    string
	PolicyPath      string
	PolicyMapPin    string
	Weights         FuseWeights
	// Track D — traffic / zero-buffer
	TrafficEnabled  bool
	TrafficAgentURL string
	RhoTarget       float64
	MuEst           float64
	MuEstSource     string
	ShedGamma       float64
	RedirectIfindex uint32
	KernelRingbuf   bool
	FastInterval    time.Duration
}

// sampleSource abstracts scrape for tests.
type sampleSource interface {
	Sample(now time.Time) (float64, error)
}

// Runner owns scrape → engine → metrics → optional semi action.
type Runner struct {
	cfg            Config
	engine         *Engine
	traffic        *TrafficEngine
	trafficScraper *TrafficScraper
	shedCtrl       *ShedController
	scraper        sampleSource
	snaps          [2]Snapshot
	idx            atomic.Uint32
	coll           *Collector
	shedder        EventShedder
	kernelSig      *KernelSignalReader
	muEst          *MuEstimator

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
	if cfg.RhoTarget <= 0 {
		cfg.RhoTarget = 0.7
	}
	if cfg.MuEst <= 0 {
		cfg.MuEst = 1000
	}
	if cfg.ShedGamma <= 0 {
		cfg.ShedGamma = 2.0
	}
	if cfg.TrafficAgentURL == "" {
		cfg.TrafficAgentURL = "http://127.0.0.1:9102/metrics"
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
	if cfg.TrafficEnabled {
		r.traffic = NewTrafficEngine(TrafficConfig{
			Horizon:        cfg.Horizon,
			RhoTarget:      cfg.RhoTarget,
			MuEst:          cfg.MuEst,
			Gamma:          cfg.ShedGamma,
			SampleInterval: cfg.Interval,
			Window:         cfg.Window,
			Alpha:          cfg.Alpha,
			AccThreshold:   cfg.AccThreshold,
		})
		r.trafficScraper = NewTrafficScraper(cfg.TrafficAgentURL)
	}
	if cfg.PolicyMapPin != "" {
		r.shedCtrl = NewShedController(cfg.ShedGamma)
		r.muEst = NewMuEstimator(cfg.MuEst)
		if cfg.KernelRingbuf {
			r.kernelSig = NewKernelSignalReader(cfg.PolicyMapPin)
		}
		if cfg.FastInterval > 0 {
			cfg.Interval = cfg.FastInterval
		} else if cfg.Interval >= time.Second {
			cfg.Interval = 50 * time.Millisecond
		}
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
	if r.kernelSig != nil {
		go r.kernelSig.Run(ctx)
	}
	t := time.NewTicker(r.cfg.Interval)
	defer t.Stop()
	log.Infof("forecaster started mode=%s interval=%s horizon=%s hardDrop=%.3fs traffic=%v",
		r.cfg.Mode, r.cfg.Interval, r.cfg.Horizon, r.cfg.HardDropSeconds, r.cfg.TrafficEnabled)

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

	xdpStats := ReadXDPStats(r.cfg.PolicyMapPin)

	var overload OverloadSnapshot
	connRate := 0.0
	if r.kernelSig != nil {
		ev := r.kernelSig.Latest()
		if ev.PktCount > 0 {
			connRate = KernelLambdaRate(ev)
		}
	}
	if r.traffic != nil {
		if connRate > 0 {
			tr := r.traffic.ObserveLambda(connRate, now)
			overload = FuseOverload(snap, tr, r.cfg.ShedGamma)
			ApplyOverload(&snap, overload)
		} else if r.trafficScraper != nil {
			if conn, err := r.trafficScraper.SampleConn(now); err == nil {
				tr := r.traffic.ObserveConn(conn, now)
				overload = FuseOverload(snap, tr, r.cfg.ShedGamma)
				ApplyOverload(&snap, overload)
			}
		}
		if r.muEst != nil {
			liveMu := r.muEst.Observe(xdpStats, snap.OverloadFraction, now)
			r.traffic.SetMuEst(liveMu)
		}
		if r.shedCtrl != nil && overload.ShedPPM > 0 {
			snap.ShedPPM = r.shedCtrl.Adjust(overload.ShedPPM, xdpStats)
		}
	}

	next := 1 - (r.idx.Load() % 2)
	r.snaps[next] = snap
	r.idx.Store(next)
	_ = WriteDecision(r.cfg.DecisionPath, snap)
	_ = WritePolicyState(r.cfg.PolicyPath, snap)
	_ = SyncPolicyToBPFMap(r.cfg.PolicyMapPin, snap, r.cfg.RedirectIfindex)

	if snap.Fault && !r.prevFault {
		r.coll.IncFaults()
		log.Warnf("forecaster FAULT cause=%s projected=%.4fs ewma=%.4fs rho=%.3f overload=%.3f shed_ppm=%d mode=%s",
			snap.Cause, snap.Projected, snap.EWMA, snap.RhoProjected, snap.OverloadFraction, snap.ShedPPM, r.cfg.Mode)
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

// PushSnapshot applies federation/controller policy without full tick.
func (r *Runner) PushSnapshot(snap Snapshot) error {
	if r == nil {
		return fmt.Errorf("runner nil")
	}
	return SyncPolicyToBPFMap(r.cfg.PolicyMapPin, snap, r.cfg.RedirectIfindex)
}

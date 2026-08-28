package dcic

import (
	"sync"
	"time"
)

// ewma is a local copy to keep Soft DCIC independent of forecaster package internals.
type ewma struct {
	alpha float64
	value float64
	init  bool
}

func newEWMA(alpha float64) ewma {
	if alpha <= 0 {
		alpha = 0.3
	}
	if alpha > 1 {
		alpha = 1
	}
	return ewma{alpha: alpha}
}

func (e *ewma) Update(x float64) float64 {
	if !e.init {
		e.value = x
		e.init = true
		return e.value
	}
	e.value = e.alpha*x + (1-e.alpha)*e.value
	return e.value
}

func (e *ewma) Value() float64 { return e.value }
func (e *ewma) Ready() bool    { return e.init }

// Decision is one control-loop output.
type Decision struct {
	Action     string // none | shrink_be | reclaim_be | advise_*
	BEQuotaPct int
	Reason     string
	Fault      bool
}

// Controller implements Soft DCIC with hysteresis (one action per dwell).
type Controller struct {
	cfg Config

	mu          sync.Mutex
	ewma        ewma
	samples     int
	slack       int
	beQuota     int
	lastAction  time.Time
	lastName    string
	snap        Snapshot
}

// NewController builds a Soft DCIC controller.
func NewController(cfg Config) *Controller {
	d := DefaultConfig()
	if cfg.Interval <= 0 {
		cfg.Interval = d.Interval
	}
	if cfg.Alpha <= 0 {
		cfg.Alpha = d.Alpha
	}
	if cfg.Window <= 0 {
		cfg.Window = d.Window
	}
	if cfg.HardDrop <= 0 {
		cfg.HardDrop = d.HardDrop
	}
	if cfg.MinDwell <= 0 {
		cfg.MinDwell = d.MinDwell
	}
	if cfg.SlackEpochs <= 0 {
		cfg.SlackEpochs = d.SlackEpochs
	}
	if cfg.BEQuotaFloor <= 0 {
		cfg.BEQuotaFloor = d.BEQuotaFloor
	}
	if cfg.BEQuotaCeil <= 0 {
		cfg.BEQuotaCeil = d.BEQuotaCeil
	}
	if cfg.StepPct <= 0 {
		cfg.StepPct = d.StepPct
	}
	if cfg.BEQuotaPct <= 0 {
		cfg.BEQuotaPct = d.BEQuotaPct
	}
	if cfg.Mode == "" {
		cfg.Mode = ModeObserve
	}
	if cfg.Track == "" {
		cfg.Track = TrackSoft
	}
	return &Controller{
		cfg:     cfg,
		ewma:    newEWMA(cfg.Alpha),
		beQuota: cfg.BEQuotaPct,
		snap: Snapshot{
			BEQuotaPct: cfg.BEQuotaPct,
			Mode:       cfg.Mode,
			Track:      cfg.Track,
		},
	}
}

// Observe folds a noise sample and returns the decision for this epoch.
func (c *Controller) Observe(noise float64, pressure float64, now time.Time) Decision {
	c.mu.Lock()
	defer c.mu.Unlock()

	c.samples++
	avg := c.ewma.Update(noise)
	fault := avg >= c.cfg.HardDrop || noise >= c.cfg.HardDrop

	dec := Decision{
		Action:     "none",
		BEQuotaPct: c.beQuota,
		Fault:      fault,
	}

	dwellOK := now.Sub(c.lastAction) >= c.cfg.MinDwell

	switch {
	case fault && dwellOK:
		next := c.beQuota - c.cfg.StepPct
		if next < c.cfg.BEQuotaFloor {
			next = c.cfg.BEQuotaFloor
		}
		if next < c.beQuota {
			dec.Action = "shrink_be"
			dec.Reason = "noise_trip"
			dec.BEQuotaPct = next
			c.slack = 0
			if c.cfg.Mode == ModeEnforce || c.cfg.Mode == ModeAdvise {
				c.beQuota = next
				c.lastAction = now
				c.lastName = dec.Action
			}
			if c.cfg.Mode == ModeAdvise {
				dec.Action = "advise_shrink_be"
			}
			if c.cfg.Mode == ModeObserve {
				dec.Action = "observe_would_shrink_be"
				dec.BEQuotaPct = c.beQuota // do not mutate in observe
			}
		}
	case !fault:
		c.slack++
		if c.slack >= c.cfg.SlackEpochs && dwellOK && c.beQuota < c.cfg.BEQuotaCeil {
			next := c.beQuota + c.cfg.StepPct
			if next > c.cfg.BEQuotaCeil {
				next = c.cfg.BEQuotaCeil
			}
			dec.Action = "reclaim_be"
			dec.Reason = "slack"
			dec.BEQuotaPct = next
			if c.cfg.Mode == ModeEnforce || c.cfg.Mode == ModeAdvise {
				c.beQuota = next
				c.slack = 0
				c.lastAction = now
				c.lastName = dec.Action
			}
			if c.cfg.Mode == ModeAdvise {
				dec.Action = "advise_reclaim_be"
			}
			if c.cfg.Mode == ModeObserve {
				dec.Action = "observe_would_reclaim_be"
				dec.BEQuotaPct = c.beQuota
			}
		}
	default:
		dec.Reason = "dwell_or_noop"
	}

	c.snap = Snapshot{
		NoiseRaw:    noise,
		NoiseEWMA:   avg,
		Pressure:    pressure,
		Fault:       fault,
		BEQuotaPct:  c.beQuota,
		LastAction:  c.lastName,
		Mode:        c.cfg.Mode,
		Track:       c.cfg.Track,
		EpochsSlack: c.slack,
		Samples:     c.samples,
	}
	return dec
}

// Snapshot returns a copy of the latest controller state.
func (c *Controller) Snapshot() Snapshot {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.snap
}

// SetMode updates actuation mode at runtime.
func (c *Controller) SetMode(mode string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.cfg.Mode = mode
	c.snap.Mode = mode
}

// BEQuota returns the enforced quota percent.
func (c *Controller) BEQuota() int {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.beQuota
}

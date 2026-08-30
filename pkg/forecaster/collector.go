package forecaster

import (
	"sync/atomic"

	"github.com/prometheus/client_golang/prometheus"
)

// Collector exposes elite_predict_* gauges/counters from a double-buffered snapshot.
type Collector struct {
	snaps  *[2]Snapshot
	idx    *atomic.Uint32
	mode   string
	faults atomic.Uint64

	descEWMA     *prometheus.Desc
	descVel      *prometheus.Desc
	descAcc      *prometheus.Desc
	descProj     *prometheus.Desc
	descFault    *prometheus.Desc
	descFaults   *prometheus.Desc
	descMode     *prometheus.Desc
	descRaw      *prometheus.Desc
	descCause    *prometheus.Desc
	descConnRate *prometheus.Desc
	descRhoProj  *prometheus.Desc
	descOverload *prometheus.Desc
	descShedPPM  *prometheus.Desc
}

// NewCollector binds to runner double-buffer slots.
func NewCollector(snaps *[2]Snapshot, idx *atomic.Uint32, mode string) *Collector {
	if mode == "" {
		mode = "dry-run"
	}
	return &Collector{
		snaps: snaps,
		idx:   idx,
		mode:  mode,
		descEWMA: prometheus.NewDesc(
			"elite_predict_latency_ewma_seconds",
			"EWMA of scraped latency proxy (seconds).",
			nil, nil,
		),
		descVel: prometheus.NewDesc(
			"elite_predict_velocity",
			"First derivative of EWMA latency (seconds/second).",
			nil, nil,
		),
		descAcc: prometheus.NewDesc(
			"elite_predict_acceleration",
			"Second derivative of EWMA latency (seconds/second^2).",
			nil, nil,
		),
		descProj: prometheus.NewDesc(
			"elite_predict_projected_5s_seconds",
			"Projected latency at forecast horizon (seconds).",
			nil, nil,
		),
		descFault: prometheus.NewDesc(
			"elite_predict_fault",
			"1 if projected latency breaches hard drop limit.",
			nil, nil,
		),
		descFaults: prometheus.NewDesc(
			"elite_predict_faults_total",
			"Count of forecast fault transitions observed.",
			nil, nil,
		),
		descMode: prometheus.NewDesc(
			"elite_predict_mode",
			"Forecast action mode (1=dry-run, 2=semi).",
			nil, nil,
		),
		descRaw: prometheus.NewDesc(
			"elite_predict_latency_raw_seconds",
			"Last raw scraped latency proxy (seconds).",
			nil, nil,
		),
		descCause: prometheus.NewDesc(
			"elite_predict_fault_cause",
			"1 when fault cause matches label (network|llc|psi|mixed).",
			[]string{"cause"}, nil,
		),
		descConnRate: prometheus.NewDesc(
			"elite_predict_conn_rate",
			"EWMA connection arrival rate (conn/s).",
			nil, nil,
		),
		descRhoProj: prometheus.NewDesc(
			"elite_predict_rho_projected",
			"Projected utilization rho at horizon (lambda/mu_est).",
			nil, nil,
		),
		descOverload: prometheus.NewDesc(
			"elite_predict_overload_fraction",
			"Overload fraction 0-1 for graduated XDP shedding.",
			nil, nil,
		),
		descShedPPM: prometheus.NewDesc(
			"elite_predict_shed_ppm",
			"Target XDP drop probability in parts per million.",
			nil, nil,
		),
	}
}

// Describe implements prometheus.Collector.
func (c *Collector) Describe(ch chan<- *prometheus.Desc) {
	ch <- c.descEWMA
	ch <- c.descVel
	ch <- c.descAcc
	ch <- c.descProj
	ch <- c.descFault
	ch <- c.descFaults
	ch <- c.descMode
	ch <- c.descRaw
	ch <- c.descCause
	ch <- c.descConnRate
	ch <- c.descRhoProj
	ch <- c.descOverload
	ch <- c.descShedPPM
}

// Collect implements prometheus.Collector.
func (c *Collector) Collect(ch chan<- prometheus.Metric) {
	var s Snapshot
	if c.snaps != nil && c.idx != nil {
		s = c.snaps[c.idx.Load()%2]
	}
	fault := 0.0
	if s.Fault {
		fault = 1
	}
	modeVal := 1.0
	if c.mode == "semi" {
		modeVal = 2
	}
	ch <- prometheus.MustNewConstMetric(c.descEWMA, prometheus.GaugeValue, s.EWMA)
	ch <- prometheus.MustNewConstMetric(c.descVel, prometheus.GaugeValue, s.Velocity)
	ch <- prometheus.MustNewConstMetric(c.descAcc, prometheus.GaugeValue, s.Acceleration)
	ch <- prometheus.MustNewConstMetric(c.descProj, prometheus.GaugeValue, s.Projected)
	ch <- prometheus.MustNewConstMetric(c.descFault, prometheus.GaugeValue, fault)
	ch <- prometheus.MustNewConstMetric(c.descFaults, prometheus.CounterValue, float64(c.faults.Load()))
	ch <- prometheus.MustNewConstMetric(c.descMode, prometheus.GaugeValue, modeVal)
	ch <- prometheus.MustNewConstMetric(c.descRaw, prometheus.GaugeValue, s.Raw)
	ch <- prometheus.MustNewConstMetric(c.descConnRate, prometheus.GaugeValue, s.ConnRate)
	ch <- prometheus.MustNewConstMetric(c.descRhoProj, prometheus.GaugeValue, s.RhoProjected)
	ch <- prometheus.MustNewConstMetric(c.descOverload, prometheus.GaugeValue, s.OverloadFraction)
	ch <- prometheus.MustNewConstMetric(c.descShedPPM, prometheus.GaugeValue, float64(s.ShedPPM))
	for _, cause := range []string{CauseNetwork, CauseLLC, CausePSI, CauseMixed} {
		v := 0.0
		if s.Fault && s.Cause == cause {
			v = 1
		}
		ch <- prometheus.MustNewConstMetric(c.descCause, prometheus.GaugeValue, v, cause)
	}
}

// IncFaults increments the fault counter (call on rising edge).
func (c *Collector) IncFaults() {
	c.faults.Add(1)
}

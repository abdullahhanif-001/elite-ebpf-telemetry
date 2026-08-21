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

	descEWMA   *prometheus.Desc
	descVel    *prometheus.Desc
	descAcc    *prometheus.Desc
	descProj   *prometheus.Desc
	descFault  *prometheus.Desc
	descFaults *prometheus.Desc
	descMode   *prometheus.Desc
	descRaw    *prometheus.Desc
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
}

// IncFaults increments the fault counter (call on rising edge).
func (c *Collector) IncFaults() {
	c.faults.Add(1)
}

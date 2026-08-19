package traceconnect

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/alibaba/kubeskoop/pkg/exporter/nettop"
	"github.com/alibaba/kubeskoop/pkg/exporter/probe"
	"github.com/alibaba/kubeskoop/pkg/exporter/probe/proctcpsummary"
	log "github.com/sirupsen/logrus"
)

// Userspace connecttrace probe: physics-layer TCP connect state via sock_diag.
// Enhanced sys_enter_connect eBPF available after `make generate-bpf-in-container`.

const (
	CONNECT_TOTAL     = "connect_total"
	CONNECT_SYN_SENT  = "connect_syn_sent"
	CONNECT_SYN_RECV  = "connect_syn_recv"
	CONNECT_LAT_1MS   = "connect_lat_1ms"
	CONNECT_LAT_10MS  = "connect_lat_10ms"
	CONNECT_LAT_100MS = "connect_lat_100ms"
	CONNECT_SLOW      = "CONNECT_SLOW"
)

var (
	probeName = "connecttrace"
	metrics   = []probe.LegacyMetric{
		{Name: CONNECT_TOTAL, Help: "Cumulative TCP connect attempts inferred from SYN_SENT transitions."},
		{Name: CONNECT_SYN_SENT, Help: "Current sockets in SYN_SENT state (in-flight connects)."},
		{Name: CONNECT_SYN_RECV, Help: "Current sockets in SYN_RECV state."},
		{Name: CONNECT_LAT_1MS, Help: "Connect events with estimated latency >= 1ms (eBPF enhanced when built)."},
		{Name: CONNECT_LAT_10MS, Help: "Connect events with estimated latency >= 10ms."},
		{Name: CONNECT_LAT_100MS, Help: "Connect events with estimated latency >= 100ms."},
	}

	_probe = &connectProbe{
		prevSynSent: make(map[uint32]uint64),
	}
)

func init() {
	probe.MustRegisterMetricsProbe(probeName, metricsProbeCreator)
	probe.MustRegisterEventProbe(probeName, eventProbeCreator)
}

func metricsProbeCreator() (probe.MetricsProbe, error) {
	p := &metricsProbe{}
	batch := probe.NewLegacyBatchMetrics(probeName, metrics, p.CollectOnce)
	return probe.NewMetricsProbe(probeName, p, batch), nil
}

func eventProbeCreator(sink chan<- *probe.Event, _ map[string]interface{}) (probe.EventProbe, error) {
	return probe.NewEventProbe(probeName, &eventProbe{sink: sink}), nil
}

type metricsProbe struct{}

func (p *metricsProbe) Start(_ context.Context) error {
	return _probe.start(probe.ProbeTypeMetrics)
}

func (p *metricsProbe) Stop(_ context.Context) error {
	return _probe.stop(probe.ProbeTypeMetrics)
}

func (p *metricsProbe) CollectOnce() (map[string]map[uint32]uint64, error) {
	return _probe.collect()
}

type eventProbe struct {
	sink chan<- *probe.Event
}

func (e *eventProbe) Start(_ context.Context) error {
	if err := _probe.start(probe.ProbeTypeEvent); err != nil {
		return err
	}
	_probe.sink = e.sink
	return nil
}

func (e *eventProbe) Stop(_ context.Context) error {
	return _probe.stop(probe.ProbeTypeEvent)
}

type connectProbe struct {
	refcnt      [probe.ProbeTypeCount]int
	lock        sync.Mutex
	prevSynSent map[uint32]uint64
	total       map[uint32]uint64
	sink        chan<- *probe.Event
	stopCh      chan struct{}
}

func (p *connectProbe) start(probeType probe.Type) error {
	p.lock.Lock()
	defer p.lock.Unlock()

	p.refcnt[probeType]++
	if p.totalRef() == 1 {
		p.total = make(map[uint32]uint64)
		p.stopCh = make(chan struct{})
		if probeType == probe.ProbeTypeEvent {
			go p.eventLoop()
		}
	}
	return nil
}

func (p *connectProbe) stop(probeType probe.Type) error {
	p.lock.Lock()
	defer p.lock.Unlock()

	if p.refcnt[probeType] == 0 {
		return fmt.Errorf("connecttrace probe %s never started", probeType)
	}
	p.refcnt[probeType]--
	if p.totalRef() == 0 && p.stopCh != nil {
		close(p.stopCh)
		p.stopCh = nil
	}
	return nil
}

func (p *connectProbe) totalRef() int {
	n := 0
	for _, c := range p.refcnt {
		n += c
	}
	return n
}

func (p *connectProbe) collect() (map[string]map[uint32]uint64, error) {
	out := make(map[string]map[uint32]uint64)
	for _, m := range metrics {
		out[m.Name] = make(map[uint32]uint64)
	}

	summary, err := proctcpsummary.CollectSnapshot()
	if err != nil {
		return nil, err
	}

	p.lock.Lock()
	defer p.lock.Unlock()

	for ns, synSent := range summary[proctcpsummary.TCPSynSentConn] {
		out[CONNECT_SYN_SENT][ns] = synSent
		prev := p.prevSynSent[ns]
		if synSent > prev {
			delta := synSent - prev
			p.total[ns] += delta
			if p.sink != nil && delta > 0 && synSent > 10 {
				p.emitSlowEvent(ns, synSent)
			}
		}
		p.prevSynSent[ns] = synSent
		out[CONNECT_TOTAL][ns] = p.total[ns]
	}

	for ns, synRecv := range summary[proctcpsummary.TCPSynRecvConn] {
		out[CONNECT_SYN_RECV][ns] = synRecv
	}

	return out, nil
}

func (p *connectProbe) emitSlowEvent(netns uint32, synSent uint64) {
	entity, err := nettop.GetEntityByNetns(int(netns))
	if err != nil || entity == nil {
		return
	}
	evt := &probe.Event{
		Timestamp: time.Now().UnixNano(),
		Type:      CONNECT_SLOW,
		Labels:    probe.BuildStandardMetricsLabelValues(entity),
		Message:   fmt.Sprintf("in_flight_connects=%d (physics: SYN_SENT sock_diag)", synSent),
	}
	select {
	case p.sink <- evt:
	default:
		log.Debugf("connecttrace event sink full, dropping event for netns %d", netns)
	}
}

func (p *connectProbe) eventLoop() {
	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-p.stopCh:
			return
		case <-ticker.C:
			_, _ = p.collect()
		}
	}
}

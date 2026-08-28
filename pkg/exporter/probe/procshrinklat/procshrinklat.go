// Package procshrinklat exposes MM reclaim pressure from /proc/vmstat (native Elite; replaces ebpf_exporter shrinklat on :9435).
package procshrinklat

import (
	"bufio"
	"context"
	"os"
	"strconv"
	"strings"

	"github.com/alibaba/kubeskoop/pkg/exporter/nettop"
	"github.com/alibaba/kubeskoop/pkg/exporter/probe"
	"github.com/prometheus/client_golang/prometheus"
)

const probeName = "shrinklat"

var vmKeys = []string{"pgscan_kswapd", "pgsteal_kswapd", "allocstall"}

func init() {
	probe.MustRegisterMetricsProbe(probeName, metricsProbeCreator)
}

func metricsProbeCreator() (probe.MetricsProbe, error) {
	p := &metricsProbe{}
	opts := probe.BatchMetricsOpts{
		Namespace:      probe.MetricsNamespace,
		Subsystem:      probeName,
		VariableLabels: probe.StandardMetricsLabels,
		SingleMetricsOpts: []probe.SingleMetricsOpts{
			{Name: "pgscan_kswapd_total", ValueType: prometheus.CounterValue},
			{Name: "pgsteal_kswapd_total", ValueType: prometheus.CounterValue},
			{Name: "allocstall_total", ValueType: prometheus.CounterValue},
		},
	}
	batch := probe.NewBatchMetrics(opts, p.collectOnce)
	return probe.NewMetricsProbe(probeName, p, batch), nil
}

type metricsProbe struct{}

func (p *metricsProbe) Start(context.Context) error { return nil }
func (p *metricsProbe) Stop(context.Context) error  { return nil }

func (p *metricsProbe) collectOnce(emit probe.Emit) error {
	vals, err := readVMStat(vmKeys)
	if err != nil {
		return err
	}
	ets := nettop.GetAllEntity()
	if len(ets) == 0 {
		labels := []string{"", "", "", ""}
		emit("pgscan_kswapd_total", labels, vals["pgscan_kswapd"])
		emit("pgsteal_kswapd_total", labels, vals["pgsteal_kswapd"])
		emit("allocstall_total", labels, vals["allocstall"])
		return nil
	}
	for _, entity := range ets {
		labels := probe.BuildStandardMetricsLabelValues(entity)
		emit("pgscan_kswapd_total", labels, vals["pgscan_kswapd"])
		emit("pgsteal_kswapd_total", labels, vals["pgsteal_kswapd"])
		emit("allocstall_total", labels, vals["allocstall"])
	}
	return nil
}

func readVMStat(want []string) (map[string]float64, error) {
	f, err := os.Open("/proc/vmstat")
	if err != nil {
		return nil, err
	}
	defer f.Close()
	out := make(map[string]float64, len(want))
	wantSet := make(map[string]struct{}, len(want))
	for _, k := range want {
		wantSet[k] = struct{}{}
	}
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		parts := strings.Fields(sc.Text())
		if len(parts) != 2 {
			continue
		}
		if _, ok := wantSet[parts[0]]; !ok {
			continue
		}
		v, err := strconv.ParseFloat(parts[1], 64)
		if err != nil {
			continue
		}
		out[parts[0]] = v
	}
	return out, sc.Err()
}

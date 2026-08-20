package export

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	dto "github.com/prometheus/client_model/go"
	log "github.com/sirupsen/logrus"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetrichttp"
	sdkmetric "go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/metric/metricdata"
	"go.opentelemetry.io/otel/sdk/resource"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
)

// Config controls OTLP export of Prometheus-gathered physics metrics.
type Config struct {
	Enabled   bool
	Endpoint  string
	Interval  time.Duration
	BatchSize int
	Service   string
}

// Bridge pushes Prometheus registry metrics to an OTLP endpoint (Google/Microsoft stack ready).
type Bridge struct {
	cfg      Config
	gatherer prometheus.Gatherer
	exporter sdkmetric.Exporter
	resource *resource.Resource
}

func NewBridge(cfg Config, gatherer prometheus.Gatherer) (*Bridge, error) {
	if !cfg.Enabled {
		return &Bridge{cfg: cfg, gatherer: gatherer}, nil
	}
	if cfg.Endpoint == "" {
		return nil, fmt.Errorf("otel endpoint required when enabled")
	}
	if cfg.Interval <= 0 {
		cfg.Interval = 15 * time.Second
	}
	if cfg.BatchSize <= 0 {
		cfg.BatchSize = 256
	}
	if cfg.Service == "" {
		cfg.Service = "elite-agent"
	}

	endpoint := strings.TrimPrefix(cfg.Endpoint, "http://")
	useTLS := strings.HasPrefix(cfg.Endpoint, "https://")
	endpoint = strings.TrimPrefix(endpoint, "https://")

	opts := []otlpmetrichttp.Option{
		otlpmetrichttp.WithEndpoint(endpoint),
	}
	if !useTLS {
		opts = append(opts, otlpmetrichttp.WithInsecure())
	}

	exp, err := otlpmetrichttp.New(context.Background(), opts...)
	if err != nil {
		return nil, fmt.Errorf("otlp exporter: %w", err)
	}

	res, _ := resource.Merge(
		resource.Default(),
		resource.NewWithAttributes(
			semconv.SchemaURL,
			semconv.ServiceName(cfg.Service),
		),
	)

	_ = res

	return &Bridge{
		cfg:      cfg,
		gatherer: gatherer,
		exporter: exp,
		resource: res,
	}, nil
}

// Run periodically gathers Prometheus metrics and exports via OTLP push reader.
func (b *Bridge) Run(ctx context.Context) {
	if !b.cfg.Enabled || b.gatherer == nil {
		return
	}

	ticker := time.NewTicker(b.cfg.Interval)
	defer ticker.Stop()

	log.Infof("elite OTel bridge started endpoint=%s interval=%s", b.cfg.Endpoint, b.cfg.Interval)

	for {
		select {
		case <-ctx.Done():
			_ = b.Shutdown(ctx)
			return
		case <-ticker.C:
			if err := b.pushOnce(ctx); err != nil {
				log.Warnf("elite OTel push: %v", err)
			}
		}
	}
}

func (b *Bridge) pushOnce(ctx context.Context) error {
	mfs, err := b.gatherer.Gather()
	if err != nil {
		return err
	}

	var metrics []metricdata.Metrics
	for _, mf := range mfs {
		if !strings.HasPrefix(mf.GetName(), "elite_") {
			continue
		}
		m, ok := promFamilyToOTel(mf)
		if ok {
			metrics = append(metrics, m)
		}
		if len(metrics) >= b.cfg.BatchSize {
			break
		}
	}

	if len(metrics) == 0 {
		return nil
	}

	rm := metricdata.ResourceMetrics{
		Resource:     b.resource,
		ScopeMetrics: []metricdata.ScopeMetrics{{Metrics: metrics}},
	}
	return b.exporter.Export(ctx, &rm)
}

func (b *Bridge) Shutdown(ctx context.Context) error {
	if b.exporter != nil {
		return b.exporter.Shutdown(ctx)
	}
	return nil
}

func promFamilyToOTel(mf *dto.MetricFamily) (metricdata.Metrics, bool) {
	name := mf.GetName()
	desc := mf.GetHelp()

	switch mf.GetType() {
	case dto.MetricType_GAUGE, dto.MetricType_COUNTER:
		var dataPoints []metricdata.DataPoint[int64]
		for _, m := range mf.GetMetric() {
			var val float64
			if mf.GetType() == dto.MetricType_GAUGE {
				val = m.GetGauge().GetValue()
			} else {
				val = m.GetCounter().GetValue()
			}
			attrs := promLabelsToAttrs(m.GetLabel())
			dataPoints = append(dataPoints, metricdata.DataPoint[int64]{
				Attributes: attrs,
				Time:       time.Now(),
				Value:      int64(val),
			})
		}
		if mf.GetType() == dto.MetricType_COUNTER {
			return metricdata.Metrics{
				Name:        name,
				Description: desc,
				Unit:        "1",
				Data:        metricdata.Sum[int64]{DataPoints: dataPoints, IsMonotonic: true},
			}, true
		}
		return metricdata.Metrics{
			Name:        name,
			Description: desc,
			Unit:        "1",
			Data:        metricdata.Gauge[int64]{DataPoints: dataPoints},
		}, true
	default:
		return metricdata.Metrics{}, false
	}
}

func promLabelsToAttrs(labels []*dto.LabelPair) attribute.Set {
	var kvs []attribute.KeyValue
	for _, l := range labels {
		kvs = append(kvs, attribute.String(l.GetName(), l.GetValue()))
	}
	return attribute.NewSet(kvs...)
}

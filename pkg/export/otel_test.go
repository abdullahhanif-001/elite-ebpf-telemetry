package export

import (
	"testing"
	"time"

	dto "github.com/prometheus/client_model/go"
)

func TestPromFamilyToOTelGauge(t *testing.T) {
	mf := &dto.MetricFamily{
		Name: ptr("elite_test_gauge"),
		Help: ptr("test"),
		Type: dto.MetricType_GAUGE.Enum(),
		Metric: []*dto.Metric{{
			Gauge: &dto.Gauge{Value: ptr(42.0)},
		}},
	}
	m, ok := promFamilyToOTel(mf)
	if !ok {
		t.Fatal("expected ok")
	}
	if m.Name != "elite_test_gauge" {
		t.Fatalf("name=%s", m.Name)
	}
}

func TestConfigDefaults(t *testing.T) {
	cfg := Config{Enabled: false}
	if cfg.Interval != 0 {
		t.Fatal("zero interval when disabled")
	}
	_ = time.Second
}

func ptr[T any](v T) *T { return &v }

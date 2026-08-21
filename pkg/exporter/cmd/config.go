package cmd

import (
	"fmt"
	"os"

	"gopkg.in/yaml.v3"
)

type InspServerConfig struct {
	DebugMode bool `yaml:"debugMode" mapstructure:"debugMode" json:"debugMode"`
	// A better way to set listen port is a `address` field  that can be used for bind interface ip, or even unix domain socket
	// Deprecated: use address instead
	Port uint16 `yaml:"port" mapstructure:"port" json:"port"`

	Address          string         `yaml:"address" mapstructure:"address" json:"address"`
	EnableController bool           `yaml:"enableController" mapstructure:"enableController" json:"enableController"`
	ControllerAddr   string         `yaml:"controllerAddr" mapstructure:"controllerAddr" json:"controllerAddr"`
	MetricsConfig    MetricsConfig  `yaml:"metrics" mapstructure:"metrics" json:"metrics"`
	EventConfig      EventConfig    `yaml:"event" mapstructure:"event" json:"event"`
	Otel             OtelConfig     `yaml:"otel" mapstructure:"otel" json:"otel"`
	Forecast         ForecastConfig `yaml:"forecast" mapstructure:"forecast" json:"forecast"`
}

// ForecastConfig drives the userspace EWMA predictive layer (no new BPF).
type ForecastConfig struct {
	Enabled         bool                   `yaml:"enabled" mapstructure:"enabled" json:"enabled"`
	Interval        string                 `yaml:"interval" mapstructure:"interval" json:"interval"`
	Horizon         string                 `yaml:"horizon" mapstructure:"horizon" json:"horizon"`
	Window          int                    `yaml:"window" mapstructure:"window" json:"window"`
	Alpha           float64                `yaml:"alpha" mapstructure:"alpha" json:"alpha"`
	HardDropSeconds float64                `yaml:"hardDropSeconds" mapstructure:"hardDropSeconds" json:"hardDropSeconds"`
	AccThreshold    float64                `yaml:"accThreshold" mapstructure:"accThreshold" json:"accThreshold"`
	Mode            string                 `yaml:"mode" mapstructure:"mode" json:"mode"`
	SemiCooldown    string                 `yaml:"semiCooldown" mapstructure:"semiCooldown" json:"semiCooldown"`
	Targets      []ForecastTargetConfig `yaml:"targets" mapstructure:"targets" json:"targets"`
}

type ForecastTargetConfig struct {
	URL    string   `yaml:"url" mapstructure:"url" json:"url"`
	Series []string `yaml:"series" mapstructure:"series" json:"series"`
}

type OtelConfig struct {
	Enabled   bool   `yaml:"enabled" mapstructure:"enabled" json:"enabled"`
	Endpoint  string `yaml:"endpoint" mapstructure:"endpoint" json:"endpoint"`
	Interval  string `yaml:"interval" mapstructure:"interval" json:"interval"`
	BatchSize int    `yaml:"batchSize" mapstructure:"batchSize" json:"batchSize"`
	Service   string `yaml:"service" mapstructure:"service" json:"service"`
}

type MetricsConfig struct {
	MetricNamespace    string        `yaml:"metricNamespace" mapstructure:"metricNamespace" json:"metricNamespace"`
	Probes             []ProbeConfig `yaml:"probes" mapstructure:"probes" json:"probes"`
	AdditionalLabels   []string      `yaml:"additionalLabels" mapstructure:"additionalLabels" json:"additionalLabels"`
	DisableCompression bool          `yaml:"disableCompression" mapstructure:"disableCompression" json:"disableCompression"`
}

type EventConfig struct {
	EventSinks []EventSinkConfig `yaml:"sinks" mapstructure:"sinks" json:"sinks"`
	Probes     []ProbeConfig     `yaml:"probes" mapstructure:"probes" json:"probes"`
}

type EventSinkConfig struct {
	Name string      `yaml:"name" mapstructure:"name" json:"name"`
	Args interface{} `yaml:"args" mapstructure:"args" json:"args"`
}

type ProbeConfig struct {
	Name string                 `yaml:"name" mapstructure:"name" json:"name"`
	Args map[string]interface{} `yaml:"args" mapstructure:"args" json:"args"`
}

func loadConfig(path string) (*InspServerConfig, error) {
	cfg := InspServerConfig{
		MetricsConfig: MetricsConfig{
			DisableCompression: true,
		},
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("failed read config file %s: %w", path, err)
	}

	if err = yaml.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("failed parse config file %s: %w", path, err)
	}

	return &cfg, nil

}

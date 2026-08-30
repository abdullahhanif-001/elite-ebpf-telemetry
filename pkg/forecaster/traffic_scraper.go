package forecaster

import (
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"
)

// TrafficScraper reads elite_tcpsummary_tcpestablishedconn from agent metrics.
type TrafficScraper struct {
	client *http.Client
	url    string
	prefix []byte
}

// NewTrafficScraper polls one Prometheus endpoint for TCP established count.
func NewTrafficScraper(agentURL string) *TrafficScraper {
	if agentURL == "" {
		agentURL = "http://127.0.0.1:9102/metrics"
	}
	return &TrafficScraper{
		client: &http.Client{
			Timeout: 800 * time.Millisecond,
			Transport: &http.Transport{
				DisableCompression: true,
			},
		},
		url:    agentURL,
		prefix: []byte("elite_tcpsummary_tcpestablishedconn"),
	}
}

// SampleConn returns established TCP connection count (sum of labeled series).
func (ts *TrafficScraper) SampleConn(now time.Time) (float64, error) {
	_ = now
	resp, err := ts.client.Get(ts.url)
	if err != nil {
		return 0, err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return 0, err
	}
	var sum float64
	for _, line := range strings.Split(string(body), "\n") {
		if strings.HasPrefix(line, "#") {
			continue
		}
		if !strings.HasPrefix(line, string(ts.prefix)) {
			continue
		}
		parts := strings.Fields(line)
		if len(parts) < 2 {
			continue
		}
		v, err := strconv.ParseFloat(parts[len(parts)-1], 64)
		if err != nil {
			continue
		}
		sum += v
	}
	if sum == 0 {
		return 0, fmt.Errorf("no %s in scrape", string(ts.prefix))
	}
	return sum, nil
}

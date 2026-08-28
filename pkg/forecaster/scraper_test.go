package forecaster

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestScraperHistogramMean(t *testing.T) {
	const body = "softirq_wait_seconds_sum 2.0\nsoftirq_wait_seconds_count 10\n"
	s := NewScraper(nil)
	v, ok := s.ParseBody([]byte(body), [][]byte{[]byte("softirq_wait_seconds")})
	if !ok {
		t.Fatal("parse failed")
	}
	if v < 0.19 || v > 0.21 {
		t.Fatalf("mean=%v want 0.2", v)
	}
}

func TestScraperSampleHTTP(t *testing.T) {
	const body = "softirq_wait_seconds_sum 2.0\nsoftirq_wait_seconds_count 10\n"
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(200)
		_, _ = w.Write([]byte(body))
	}))
	defer srv.Close()

	s := NewScraper([]Target{{URL: srv.URL, Series: []string{"softirq_wait_seconds"}}})
	v, err := s.Sample(time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if v < 0.19 || v > 0.21 {
		t.Fatalf("mean=%v want 0.2", v)
	}
}

func TestScraperCounterRate(t *testing.T) {
	var n int
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		n++
		val := 100
		if n > 1 {
			val = 200
		}
		w.WriteHeader(200)
		_, _ = w.Write([]byte(fmt.Sprintf("elite_socketlatency_read100ms %d\n", val)))
	}))
	defer srv.Close()

	s := NewScraper([]Target{{URL: srv.URL, Series: []string{"elite_socketlatency"}}})
	now := time.Now()
	_, _ = s.Sample(now)
	v, err := s.Sample(now.Add(time.Second))
	if err != nil {
		t.Fatal(err)
	}
	if v < 0.09 || v > 0.11 {
		t.Fatalf("rate proxy=%v want ~0.1", v)
	}
}
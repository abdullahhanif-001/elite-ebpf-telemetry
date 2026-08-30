package elitecontroller

import "testing"

func TestScrapeNodeEmpty(t *testing.T) {
	_, _, ok := scrapeNode("http://127.0.0.1:1/metrics")
	if ok {
		t.Fatal("expected fail on bad url")
	}
}

func TestFederatorSnapshot(t *testing.T) {
	f := NewFederator(Config{NodeURLs: []string{"http://127.0.0.1:9102/metrics"}})
	s := f.Snapshot()
	if s.NodeCount != 0 {
		t.Fatalf("node_count=%d", s.NodeCount)
	}
}

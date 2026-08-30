// Elite-controller — federates overload and pushes policy to nodes.
package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/alibaba/kubeskoop/pkg/elitecontroller"
)

func main() {
	addr := os.Getenv("ELITE_CONTROLLER_ADDR")
	if addr == "" {
		addr = ":9200"
	}
	nodes := os.Getenv("ELITE_CONTROLLER_NODES")
	if nodes == "" {
		nodes = "http://127.0.0.1:9102/metrics"
	}
	pushURLs := os.Getenv("ELITE_CONTROLLER_PUSH_URLS")
	interval := 500 * time.Millisecond
	if v := os.Getenv("ELITE_CONTROLLER_INTERVAL"); v != "" {
		if d, err := time.ParseDuration(v); err == nil {
			interval = d
		}
	}
	token := os.Getenv("ELITE_CONTROLLER_PUSH_TOKEN")

	fed := elitecontroller.NewFederator(elitecontroller.Config{
		NodeURLs:   strings.Split(nodes, ","),
		Interval:   interval,
		RhoCap:     0.85,
		PolicyPath: "/var/lib/elite/federated-policy.json",
	})
	go fed.Run()

	if pushURLs != "" {
		p := elitecontroller.NewPusher(fed, elitecontroller.PushConfig{
			NodePushURLs: strings.Split(pushURLs, ","),
			Token:        token,
			Interval:     interval,
			RhoCap:       0.85,
		})
		go p.Run()
	}

	http.HandleFunc("/health", func(w http.ResponseWriter, _ *http.Request) {
		w.Write([]byte("ok"))
	})
	http.HandleFunc("/policy", func(w http.ResponseWriter, _ *http.Request) {
		p := fed.Snapshot()
		_ = json.NewEncoder(w).Encode(p)
	})
	log.Printf("elite-controller listening %s interval=%s", addr, interval)
	log.Fatal(http.ListenAndServe(addr, nil))
}

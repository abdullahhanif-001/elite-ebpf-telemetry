package forecaster

import (
	"io"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"
)

func scrapeLLCMissRate(url string) (float64, bool) {
	client := &http.Client{Timeout: 400 * time.Millisecond}
	resp, err := client.Get(url)
	if err != nil {
		return 0, false
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, 64<<10))
	if err != nil {
		return 0, false
	}
	en := false
	var missRate float64
	for _, line := range strings.Split(string(body), "\n") {
		if strings.HasPrefix(line, "elite_llc_enabled ") {
			f := strings.Fields(line)
			if len(f) >= 2 && (f[1] == "1" || f[1] == "1.0") {
				en = true
			}
		}
		if strings.HasPrefix(line, "elite_llc_miss_rate ") {
			f := strings.Fields(line)
			if len(f) >= 2 {
				missRate, _ = strconv.ParseFloat(f[1], 64)
			}
		}
	}
	if !en {
		return 0, false
	}
	return missRate, true
}

func readPSISomeAvg10() (float64, bool) {
	b, err := os.ReadFile("/proc/pressure/cpu")
	if err != nil {
		return 0, false
	}
	for _, line := range strings.Split(string(b), "\n") {
		if !strings.HasPrefix(line, "some ") {
			continue
		}
		for _, f := range strings.Fields(line) {
			if strings.HasPrefix(f, "avg10=") {
				v, err := strconv.ParseFloat(strings.TrimPrefix(f, "avg10="), 64)
				return v, err == nil
			}
		}
	}
	return 0, false
}

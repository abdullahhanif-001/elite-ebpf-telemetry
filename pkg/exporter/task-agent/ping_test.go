package taskagent

import (
	"net"
	"testing"
)

func TestGetLatency(t *testing.T) {
	dst := net.IPv4(8, 8, 8, 8).String()
	pingStr := "PING " + dst + " (" + dst + "): 56 data bytes\n\n--- " + dst + " ping statistics ---\n100 packets transmitted, 100 packets received, 0% packet loss\nround-trip min/avg/max = 43.689/43.720/43.809 ms"
	lMin, lAvg, lMax, err := getLatency(pingStr)
	if err != nil {
		t.Fatal(err.Error())
	}
	if lMin != 43.689 || lAvg != 43.720 || lMax != 43.809 {
		t.Fatal("min/avg/max is not correct")
	}
	t.Logf("min/avg/max is %v, %v, %v", lMin, lAvg, lMax)
}

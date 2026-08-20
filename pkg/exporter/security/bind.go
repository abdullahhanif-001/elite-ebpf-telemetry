package security

import (
	"fmt"
	"net"
	"os"
	"strings"
)

// ValidateListenAddress rejects non-loopback binds unless explicitly allowed.
func ValidateListenAddress(raw string) error {
	host := raw
	if strings.Contains(raw, "://") {
		s := strings.TrimPrefix(strings.TrimPrefix(raw, "tcp://"), "unix://")
		if h, _, err := net.SplitHostPort(s); err == nil {
			host = h
		} else {
			host = s
		}
	} else if h, _, err := net.SplitHostPort(raw); err == nil {
		host = h
	}

	host = strings.Trim(host, "[]")
	if host == "" || host == "0.0.0.0" || host == "::" {
		if os.Getenv("ELITE_ALLOW_PUBLIC_BIND") == "1" {
			return nil
		}
		return fmt.Errorf("refusing to bind %q: use 127.0.0.1 or set ELITE_ALLOW_PUBLIC_BIND=1", raw)
	}

	ip := net.ParseIP(host)
	if ip == nil {
		return nil
	}
	if ip.IsLoopback() {
		return nil
	}
	if os.Getenv("ELITE_ALLOW_PUBLIC_BIND") == "1" {
		return nil
	}
	return fmt.Errorf("refusing non-loopback bind %q", host)
}

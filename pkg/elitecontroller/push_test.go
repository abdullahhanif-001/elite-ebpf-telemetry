package elitecontroller

import (
	"testing"
	"time"
)

func TestNewPusher(t *testing.T) {
	f := NewFederator(Config{Interval: time.Second})
	p := NewPusher(f, PushConfig{
		NodePushURLs: []string{"http://127.0.0.1:1/policy"},
		Interval:     100 * time.Millisecond,
	})
	if p == nil {
		t.Fatal("nil pusher")
	}
}

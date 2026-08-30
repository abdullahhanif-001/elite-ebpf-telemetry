package forecaster

import (
	"context"
	"encoding/binary"
	"fmt"
	"os"
	"sync"
	"time"

	"github.com/cilium/ebpf"
	"github.com/cilium/ebpf/ringbuf"
	log "github.com/sirupsen/logrus"
)

// LambdaEvent mirrors bpf elite_lambda_event.
type LambdaEvent struct {
	TsNs      uint64
	PktCount  uint32
	SynCount  uint32
	PassCount uint32
	DropCount uint32
}

// KernelSignalReader consumes ringbuf λ events from pinned elite_lambda_ring.
type KernelSignalReader struct {
	pinPath string
	reader  *ringbuf.Reader
	mu      sync.Mutex
	last    LambdaEvent
}

// NewKernelSignalReader opens pinned ringbuf if present.
func NewKernelSignalReader(policyPin string) *KernelSignalReader {
	if policyPin == "" {
		return nil
	}
	dir := policyPin
	if len(policyPin) > 6 && policyPin[len(policyPin)-6:] == "policy" {
		dir = policyPin[:len(policyPin)-len("policy")]
	}
	ringPin := dir + "lambda_ring"
	if _, err := os.Stat(ringPin); err != nil {
		ringPin = dir + "elite_lambda_ring"
		if _, err2 := os.Stat(ringPin); err2 != nil {
			return nil
		}
	}
	m, err := ebpf.LoadPinnedMap(ringPin, nil)
	if err != nil {
		log.Debugf("kernel signal map: %v", err)
		return nil
	}
	r, err := ringbuf.NewReader(m)
	if err != nil {
		m.Close()
		log.Debugf("kernel signal ringbuf: %v", err)
		return nil
	}
	return &KernelSignalReader{pinPath: ringPin, reader: r}
}

// Run drains ringbuf until ctx cancelled.
func (k *KernelSignalReader) Run(ctx context.Context) {
	if k == nil || k.reader == nil {
		return
	}
	defer k.reader.Close()
	for {
		select {
		case <-ctx.Done():
			return
		default:
		}
		rec, err := k.reader.Read()
		if err != nil {
			if ctx.Err() != nil {
				return
			}
			time.Sleep(10 * time.Millisecond)
			continue
		}
		ev, err := decodeLambdaEvent(rec.RawSample)
		if err != nil {
			continue
		}
		k.mu.Lock()
		k.last = ev
		k.mu.Unlock()
	}
}

// Latest returns last observed batch event.
func (k *KernelSignalReader) Latest() LambdaEvent {
	if k == nil {
		return LambdaEvent{}
	}
	k.mu.Lock()
	defer k.mu.Unlock()
	return k.last
}

func decodeLambdaEvent(b []byte) (LambdaEvent, error) {
	if len(b) < 32 {
		return LambdaEvent{}, fmt.Errorf("short lambda event %d", len(b))
	}
	return LambdaEvent{
		TsNs:      binary.LittleEndian.Uint64(b[0:8]),
		PktCount:  binary.LittleEndian.Uint32(b[8:12]),
		SynCount:  binary.LittleEndian.Uint32(b[12:16]),
		PassCount: binary.LittleEndian.Uint32(b[16:20]),
		DropCount: binary.LittleEndian.Uint32(b[20:24]),
	}, nil
}

// KernelLambdaRate estimates pkt/s from latest ringbuf batch.
func KernelLambdaRate(ev LambdaEvent) float64 {
	if ev.PktCount == 0 {
		return 0
	}
	// batch covers ~1024 packets at line rate; approximate 1s window scaling
	return float64(ev.PktCount) * 100.0
}

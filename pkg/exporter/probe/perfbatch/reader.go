package perfbatch

import (
	"context"
	"time"

	"github.com/cilium/ebpf"
	"github.com/cilium/ebpf/perf"
	log "github.com/sirupsen/logrus"
)

const (
	// DefaultWakeupEvents is the perf ring buffer wakeup watermark (events).
	DefaultWakeupEvents = 256
	// DefaultReadTimeout bounds blocking perf reads.
	DefaultReadTimeout = 2 * time.Second
)

// Reader wraps perf.Reader with timeout-bounded batch reads and drop accounting.
type Reader struct {
	inner      *perf.Reader
	probeName  string
	drops      uint64
	reads      uint64
}

func NewReader(probeName string, m *ebpf.Map, recordSize int) (*Reader, error) {
	r, err := perf.NewReader(m, recordSize*DefaultWakeupEvents)
	if err != nil {
		return nil, err
	}
	return &Reader{inner: r, probeName: probeName}, nil
}

func (r *Reader) Close() error {
	if r.inner == nil {
		return nil
	}
	return r.inner.Close()
}

func (r *Reader) Drops() uint64  { return r.drops }
func (r *Reader) Reads() uint64  { return r.reads }

// Read blocks up to DefaultReadTimeout for the next perf record.
func (r *Reader) Read(ctx context.Context) (perf.Record, error) {
	deadline, ok := ctx.Deadline()
	if !ok {
		deadline = time.Now().Add(DefaultReadTimeout)
	}
	timer := time.NewTimer(time.Until(deadline))
	defer timer.Stop()

	type result struct {
		rec perf.Record
		err error
	}
	ch := make(chan result, 1)
	go func() {
		rec, err := r.inner.Read()
		ch <- result{rec, err}
	}()

	select {
	case <-ctx.Done():
		return perf.Record{}, ctx.Err()
	case <-timer.C:
		return perf.Record{}, context.DeadlineExceeded
	case out := <-ch:
		r.reads++
		if out.rec.LostSamples > 0 {
			r.drops += out.rec.LostSamples
			log.Infof("%s perf ring buffer drop: %d (total drops: %d)", r.probeName, out.rec.LostSamples, r.drops)
		}
		return out.rec, out.err
	}
}

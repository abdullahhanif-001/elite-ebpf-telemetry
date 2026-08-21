package forecaster

import "sync"

const maxRingCap = 16

// Ring is a fixed-capacity sliding window of float64 samples.
// Push and Snapshot never allocate after construction.
type Ring struct {
	mu   sync.Mutex
	buf  [maxRingCap]float64
	cap  int
	len  int
	head int // next write index
}

// NewRing returns a ring with capacity n (clamped to [2, maxRingCap]).
func NewRing(n int) *Ring {
	if n < 2 {
		n = 2
	}
	if n > maxRingCap {
		n = maxRingCap
	}
	return &Ring{cap: n}
}

// Push appends v, overwriting the oldest sample when full.
func (r *Ring) Push(v float64) {
	r.mu.Lock()
	r.buf[r.head] = v
	r.head = (r.head + 1) % r.cap
	if r.len < r.cap {
		r.len++
	}
	r.mu.Unlock()
}

// Len returns the number of valid samples.
func (r *Ring) Len() int {
	r.mu.Lock()
	n := r.len
	r.mu.Unlock()
	return n
}

// Snapshot copies samples in chronological order into dst.
// dst must have length >= ring capacity; returns count written.
func (r *Ring) Snapshot(dst []float64) int {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.len == 0 || len(dst) == 0 {
		return 0
	}
	n := r.len
	if n > len(dst) {
		n = len(dst)
	}
	start := 0
	if r.len == r.cap {
		start = r.head
	}
	for i := 0; i < n; i++ {
		dst[i] = r.buf[(start+i)%r.cap]
	}
	return n
}

package bpfutil

import (
	"runtime"
	"testing"

	"github.com/cilium/ebpf"
)

func TestUpdateFeatureSwitch(t *testing.T) {
	if runtime.GOOS != "linux" {
		t.Skip("linux only")
	}
	numCPUs := runtime.NumCPU()
	m, err := ebpf.NewMap(&ebpf.MapSpec{
		Type:       ebpf.Array,
		KeySize:    4,
		ValueSize:  uint32(numCPUs),
		MaxEntries: 4,
	})
	if err != nil {
		t.Skipf("cannot create map: %v", err)
	}
	defer m.Close()
	if err := UpdateFeatureSwitch(m, 0, 1); err != nil {
		t.Fatal(err)
	}
	var out []uint8
	out = make([]uint8, numCPUs)
	if err := m.Lookup(uint32(0), &out); err != nil {
		t.Fatal(err)
	}
	if out[0] != 1 {
		t.Fatalf("value=%d want 1", out[0])
	}
}

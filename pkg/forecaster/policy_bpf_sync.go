package forecaster

import (
	"encoding/binary"
	"fmt"
	"os"
	"sync"
	"sync/atomic"

	"github.com/cilium/ebpf"
)

const bpfPolicyValueLen = 32
const bpfPolicyKeyGlobal = uint32(0)

var (
	policyMapMu   sync.Mutex
	policyMapPin  string
	policyMap     *ebpf.Map
)

type bpfPolicyValue struct {
	PolicyVersion uint64
	Fault         uint8
	Cause         uint8
	Pad           [6]uint8
	ProjectedNs   uint64
	EwmaNs        uint64
}

// SyncPolicyToBPFMap updates pinned elite_policy map (fast cilium/ebpf path).
func SyncPolicyToBPFMap(pinPath string, snap Snapshot) error {
	if pinPath == "" {
		return nil
	}
	if _, err := os.Stat(pinPath); err != nil {
		return nil
	}

	m, err := openPolicyMap(pinPath)
	if err != nil {
		return err
	}

	ver := atomic.LoadUint64(&policySeq)
	val := bpfPolicyValue{
		PolicyVersion: ver,
		Fault:         0,
		Cause:         causeToPolicyCode(snap.Cause),
		ProjectedNs:   uint64(snap.Projected * 1e9),
		EwmaNs:        uint64(snap.EWMA * 1e9),
	}
	if snap.Fault {
		val.Fault = 1
	}

	key := bpfPolicyKeyGlobal
	return m.Update(key, &val, ebpf.UpdateAny)
}

func openPolicyMap(pinPath string) (*ebpf.Map, error) {
	policyMapMu.Lock()
	defer policyMapMu.Unlock()

	if policyMap != nil && policyMapPin == pinPath {
		return policyMap, nil
	}
	if policyMap != nil {
		policyMap.Close()
		policyMap = nil
	}

	m, err := ebpf.LoadPinnedMap(pinPath, nil)
	if err != nil {
		return nil, fmt.Errorf("load pinned policy map: %w", err)
	}
	policyMapPin = pinPath
	policyMap = m
	return m, nil
}

// PolicyMapFaultByte reads fault byte from pinned map for parity proofs.
func PolicyMapFaultByte(pinPath string) (uint8, error) {
	m, err := openPolicyMap(pinPath)
	if err != nil {
		return 0, err
	}
	var val bpfPolicyValue
	key := bpfPolicyKeyGlobal
	if err := m.Lookup(key, &val); err != nil {
		return 0, err
	}
	return val.Fault, nil
}

// EncodeBPFPolicyValue exports 32-byte map encoding for tests.
func EncodeBPFPolicyValue(snap Snapshot, ver uint64) []byte {
	out := make([]byte, bpfPolicyValueLen)
	binary.LittleEndian.PutUint64(out[0:8], ver)
	if snap.Fault {
		out[8] = 1
	}
	out[9] = causeToPolicyCode(snap.Cause)
	binary.LittleEndian.PutUint64(out[16:24], uint64(snap.Projected*1e9))
	binary.LittleEndian.PutUint64(out[24:32], uint64(snap.EWMA*1e9))
	return out
}

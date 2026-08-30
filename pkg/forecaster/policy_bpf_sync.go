package forecaster

import (
	"encoding/binary"
	"fmt"
	"os"
	"strings"
	"sync"
	"sync/atomic"

	"github.com/cilium/ebpf"
)

const bpfPolicyValueLen = 80
const bpfPolicyKeyGlobal = uint32(0)
const elitePolicyVersionV2 = 2
const elitePolicyVersionV3 = 3

var (
	policyMapMu  sync.Mutex
	policyMapPin string
	policyMap    *ebpf.Map
	xdpStatsPin  string
	xdpStatsMap  *ebpf.Map
)

type bpfPolicyValue struct {
	PolicyVersion   uint64
	Fault           uint8
	Cause           uint8
	Actuate         uint8
	Pad             [5]uint8
	ProjectedNs     uint64
	EwmaNs          uint64
	OverloadPPM     uint32
	ShedPPM         uint32
	RedirectIfindex uint32
	TierRefillPPM   [4]uint32
	MuTokensPerSec  uint32
	RhoProjPPM      uint64
	EscalateFlags   uint32
	PadEnd          uint32
}

type bpfXDPStat struct {
	Pass     uint64
	Drop     uint64
	Redirect uint64
}

// DefaultTierRefillPPM returns tier refill rates (ppm of mu).
func DefaultTierRefillPPM() [4]uint32 {
	return [4]uint32{ppmScale, ppmScale / 2, ppmScale / 10, 0}
}

// SyncPolicyToBPFMap updates pinned elite_policy map (fast cilium/ebpf path).
func SyncPolicyToBPFMap(pinPath string, snap Snapshot, redirectIfindex uint32) error {
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

	_ = atomic.AddUint64(&policySeq, 1)
	tiers := DefaultTierRefillPPM()
	mu := uint32(snap.ConnRate)
	if mu == 0 {
		mu = 10000
	}
	if snap.RhoProjected > 0 && snap.RhoProjected < 1 {
		mu = uint32(float64(mu) / snap.RhoProjected)
	}

	val := bpfPolicyValue{
		PolicyVersion:   elitePolicyVersionV3,
		Cause:           causeToPolicyCode(snap.Cause),
		Actuate:         1,
		ProjectedNs:     uint64(snap.Projected * 1e9),
		EwmaNs:          uint64(snap.EWMA * 1e9),
		OverloadPPM:     uint32(snap.OverloadFraction * float64(ppmScale)),
		ShedPPM:         snap.ShedPPM,
		RedirectIfindex: redirectIfindex,
		TierRefillPPM:   tiers,
		MuTokensPerSec:  mu,
		RhoProjPPM:      uint64(snap.RhoProjected * float64(ppmScale)),
	}
	if snap.Fault {
		val.Fault = 1
	}
	if val.ShedPPM == 0 && snap.Fault {
		val.ShedPPM = ppmScale
	}
	if snap.RhoProjected > 0.6 {
		val.EscalateFlags |= 1 // PORT_FILTER placeholder
	}
	if snap.RhoProjected > 0.85 {
		val.EscalateFlags |= 2 // SYN_PROXY
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

// ReadXDPStats reads per-CPU aggregated pass/drop from elite_xdp_stats if pinned.
func ReadXDPStats(policyPin string) XDPStats {
	stats := XDPStats{}
	if policyPin == "" {
		return stats
	}
	dir := policyPin
	if strings.HasSuffix(policyPin, "policy") {
		dir = policyPin[:len(policyPin)-len("policy")]
	}
	statsPin := dir + "xdp_stats"
	m, err := openXDPStatsMap(statsPin)
	if err != nil {
		return stats
	}
	key := uint32(0)
	if m.Type() == ebpf.PerCPUArray {
		var vals []bpfXDPStat
		if err := m.Lookup(key, &vals); err != nil {
			return stats
		}
		for _, v := range vals {
			stats.Pass += v.Pass
			stats.Drop += v.Drop
			stats.Redirect += v.Redirect
		}
		return stats
	}
	var val bpfXDPStat
	if err := m.Lookup(key, &val); err != nil {
		return stats
	}
	stats.Pass = val.Pass
	stats.Drop = val.Drop
	stats.Redirect = val.Redirect
	return stats
}

func openXDPStatsMap(pinPath string) (*ebpf.Map, error) {
	policyMapMu.Lock()
	defer policyMapMu.Unlock()
	if _, err := os.Stat(pinPath); err != nil {
		return nil, err
	}
	if xdpStatsMap != nil && xdpStatsPin == pinPath {
		return xdpStatsMap, nil
	}
	if xdpStatsMap != nil {
		xdpStatsMap.Close()
		xdpStatsMap = nil
	}
	m, err := ebpf.LoadPinnedMap(pinPath, nil)
	if err != nil {
		return nil, err
	}
	xdpStatsPin = pinPath
	xdpStatsMap = m
	return m, nil
}

// XDPStats aggregates kernel XDP pass/drop counters.
type XDPStats struct {
	Pass, Drop, Redirect uint64
}

// EncodeBPFPolicyValue exports map encoding for tests.
func EncodeBPFPolicyValue(snap Snapshot, ver uint64) []byte {
	out := make([]byte, bpfPolicyValueLen)
	binary.LittleEndian.PutUint64(out[0:8], ver)
	if snap.Fault {
		out[8] = 1
	}
	out[9] = causeToPolicyCode(snap.Cause)
	out[10] = 1 // actuate
	binary.LittleEndian.PutUint64(out[16:24], uint64(snap.Projected*1e9))
	binary.LittleEndian.PutUint64(out[24:32], uint64(snap.EWMA*1e9))
	binary.LittleEndian.PutUint32(out[32:36], uint32(snap.OverloadFraction*float64(ppmScale)))
	binary.LittleEndian.PutUint32(out[36:40], snap.ShedPPM)
	binary.LittleEndian.PutUint64(out[64:72], uint64(snap.RhoProjected*float64(ppmScale)))
	return out
}

// PushPolicySnapshot writes an explicit snapshot (federation push).
func PushPolicySnapshot(pinPath string, snap Snapshot, redirectIfindex uint32) error {
	return SyncPolicyToBPFMap(pinPath, snap, redirectIfindex)
}

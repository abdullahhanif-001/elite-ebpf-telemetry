package forecaster

// Cause labels for elite_predict_fault_cause (deterministic argmax).
const (
	CauseNone    = "none"
	CauseNetwork = "network"
	CauseLLC     = "llc"
	CausePSI     = "psi"
	CauseMixed   = "mixed"
)

// SignalVector holds normalized physics proxies in roughly "seconds-equivalent" space.
type SignalVector struct {
	Network float64 // softirq / socketlatency proxy (seconds)
	LLC     float64 // miss-rate mapped to [0, hardDrop*2] scale
	PSI     float64 // PSI some avg10 mapped similarly
	HasLLC  bool
	HasPSI  bool
}

// FuseWeights are relative weights for the fused scalar fed to the kinematic engine.
type FuseWeights struct {
	Network float64
	LLC     float64
	PSI     float64
}

// DefaultFuseWeights favors network physics, then LLC, then PSI.
func DefaultFuseWeights() FuseWeights {
	return FuseWeights{Network: 0.6, LLC: 0.25, PSI: 0.15}
}

// FuseScalar weighted-average of available signals.
func FuseScalar(v SignalVector, w FuseWeights) float64 {
	var sum, wt float64
	sum += w.Network * v.Network
	wt += w.Network
	if v.HasLLC {
		sum += w.LLC * v.LLC
		wt += w.LLC
	}
	if v.HasPSI {
		sum += w.PSI * v.PSI
		wt += w.PSI
	}
	if wt <= 0 {
		return v.Network
	}
	return sum / wt
}

// BlameCause returns causal tag by argmax of normalized excess over hardDrop*0.3.
func BlameCause(v SignalVector, hardDrop float64) string {
	floor := hardDrop * 0.3
	nEx := v.Network - floor
	if nEx < 0 {
		nEx = 0
	}
	lEx := 0.0
	if v.HasLLC {
		lEx = v.LLC - floor
		if lEx < 0 {
			lEx = 0
		}
	}
	pEx := 0.0
	if v.HasPSI {
		pEx = v.PSI - floor
		if pEx < 0 {
			pEx = 0
		}
	}
	if nEx == 0 && lEx == 0 && pEx == 0 {
		return CauseNone
	}
	// mixed if two signals both material (>50% of max excess)
	max := nEx
	cause := CauseNetwork
	if lEx > max {
		max = lEx
		cause = CauseLLC
	}
	if pEx > max {
		max = pEx
		cause = CausePSI
	}
	if max <= 0 {
		return CauseNone
	}
	second := 0
	if nEx > max*0.5 && cause != CauseNetwork {
		second++
	}
	if lEx > max*0.5 && cause != CauseLLC {
		second++
	}
	if pEx > max*0.5 && cause != CausePSI {
		second++
	}
	if second > 0 {
		return CauseMixed
	}
	return cause
}

// MapLLCMissRate maps misses/sec into a latency-like proxy (seconds scale).
func MapLLCMissRate(missRate, hardDrop float64) float64 {
	// 1e6 misses/s ≈ hardDrop scale (tunable constant)
	const ref = 1_000_000.0
	if missRate <= 0 {
		return 0
	}
	x := (missRate / ref) * hardDrop
	if x > hardDrop*4 {
		x = hardDrop * 4
	}
	return x
}

// MapPSI maps PSI some avg10 (percent-ish 0-100) into seconds-like proxy.
func MapPSI(avg10, hardDrop float64) float64 {
	if avg10 <= 0 {
		return 0
	}
	x := (avg10 / 100.0) * hardDrop * 2
	if x > hardDrop*4 {
		x = hardDrop * 4
	}
	return x
}

// ShouldShedEvents is true for network-dominated faults (semi mode).
func ShouldShedEvents(cause string) bool {
	return cause == CauseNetwork || cause == CauseMixed
}

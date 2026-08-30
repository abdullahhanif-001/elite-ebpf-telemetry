package forecaster

// OverloadSnapshot merges latency and traffic physics for actuation.
type OverloadSnapshot struct {
	Latency       Snapshot
	Traffic       TrafficSnapshot
	Overload      float64
	ShedPPM       uint32
	CombinedFault bool
}

// FuseOverload merges latency fault and traffic pre-fault into actuation outputs.
func FuseOverload(lat Snapshot, traffic TrafficSnapshot, gamma float64) OverloadSnapshot {
	o := traffic.Overload
	if lat.Fault {
		latO := ComputeOverloadFraction(lat.Projected/(lat.EWMA+1e-9), 1.0)
		if latO > o {
			o = latO
		}
		if o < 0.5 {
			o = 0.5
		}
	}
	combined := lat.Fault || traffic.PreFault
	return OverloadSnapshot{
		Latency:       lat,
		Traffic:       traffic,
		Overload:      o,
		ShedPPM:       ShedPPM(o, gamma),
		CombinedFault: combined,
	}
}

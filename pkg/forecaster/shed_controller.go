package forecaster

// ShedController PI-adjusts shed_ppm based on XDP drop feedback.
type ShedController struct {
	gamma   float64
	lastPPM uint32
}

// NewShedController builds a shed rate adjuster.
func NewShedController(gamma float64) *ShedController {
	if gamma <= 0 {
		gamma = 2
	}
	return &ShedController{gamma: gamma}
}

// Adjust returns shed_ppm possibly reduced when drops overshoot target overload.
func (s *ShedController) Adjust(targetPPM uint32, stats XDPStats) uint32 {
	if targetPPM == 0 {
		s.lastPPM = 0
		return 0
	}
	total := stats.Pass + stats.Drop
	if total < 100 {
		s.lastPPM = targetPPM
		return targetPPM
	}
	dropRate := float64(stats.Drop) / float64(total)
	targetRate := float64(targetPPM) / float64(ppmScale)
	if dropRate > targetRate*1.2 {
		adj := uint32(float64(targetPPM) * 0.9)
		if adj < targetPPM/2 {
			adj = targetPPM / 2
		}
		s.lastPPM = adj
		return adj
	}
	s.lastPPM = targetPPM
	return targetPPM
}

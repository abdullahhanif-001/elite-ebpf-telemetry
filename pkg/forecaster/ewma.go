package forecaster

// EWMA is an exponentially weighted moving average.
type EWMA struct {
	alpha float64
	value float64
	init  bool
}

// NewEWMA creates an EWMA with smoothing factor alpha in (0,1].
func NewEWMA(alpha float64) EWMA {
	if alpha <= 0 {
		alpha = 0.3
	}
	if alpha > 1 {
		alpha = 1
	}
	return EWMA{alpha: alpha}
}

// Update folds x into the average and returns the new value.
func (e *EWMA) Update(x float64) float64 {
	if !e.init {
		e.value = x
		e.init = true
		return e.value
	}
	e.value = e.alpha*x + (1-e.alpha)*e.value
	return e.value
}

// Value returns the current average (0 if never updated).
func (e *EWMA) Value() float64 {
	return e.value
}

// Ready reports whether at least one sample was observed.
func (e *EWMA) Ready() bool {
	return e.init
}

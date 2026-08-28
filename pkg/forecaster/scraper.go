package forecaster

import (
	"fmt"
	"io"
	"net/http"
	"time"
)

const (
	scrapeBufCap   = 256 << 10
	maxSeriesSlots = 32
)

// Target is one localhost Prometheus exposition endpoint.
type Target struct {
	URL    string
	Series []string // metric name prefixes
}

// Scraper polls Prometheus text endpoints with reusable buffers (zero-alloc parse path).
type Scraper struct {
	client  *http.Client
	targets []Target

	// reusable body buffers (fetch path)
	body    []byte
	readBuf []byte

	// precomputed series prefixes as []byte (built once)
	seriesBytes [][][]byte // [target][series]

	// fixed counter slots: last values for rate proxy (no map)
	lastCounter [maxSeriesSlots]float64
	haveCounter [maxSeriesSlots]bool
	lastAt      time.Time

	// scratch for suffix matching without string concat
	sumScratch   [128]byte
	countScratch [128]byte
}

// NewScraper builds a scraper for the given targets.
func NewScraper(targets []Target) *Scraper {
	s := &Scraper{
		client: &http.Client{
			Timeout: 800 * time.Millisecond,
			Transport: &http.Transport{
				MaxIdleConns:        4,
				IdleConnTimeout:     30 * time.Second,
				DisableCompression:  true,
				MaxIdleConnsPerHost: 2,
			},
		},
		targets: targets,
		body:    make([]byte, 0, scrapeBufCap),
		readBuf: make([]byte, scrapeBufCap),
	}
	s.seriesBytes = make([][][]byte, len(targets))
	slot := 0
	for i, t := range targets {
		s.seriesBytes[i] = make([][]byte, len(t.Series))
		for j, p := range t.Series {
			s.seriesBytes[i][j] = []byte(p)
			slot++
			if slot >= maxSeriesSlots {
				break
			}
		}
	}
	return s
}

func slotIndex(targetIdx, seriesIdx int) int {
	return targetIdx*8 + seriesIdx
}

// Sample scrapes all targets and returns a combined latency proxy in seconds.
func (s *Scraper) Sample(now time.Time) (float64, error) {
	var (
		sumMean float64
		meanN   int
		sumRate float64
		rateN   int
		anyOK   bool
		lastErr error
	)

	for ti, t := range s.targets {
		body, err := s.fetch(t.URL)
		if err != nil {
			lastErr = err
			continue
		}
		anyOK = true
		for si := range t.Series {
			prefix := s.seriesBytes[ti][si]
			if m, ok := s.histogramMean(body, prefix); ok {
				sumMean += m
				meanN++
				continue
			}
			if c, ok := counterTotalBytes(body, prefix); ok {
				idx := slotIndex(ti, si)
				if idx < maxSeriesSlots && s.haveCounter[idx] && !s.lastAt.IsZero() {
					dt := now.Sub(s.lastAt).Seconds()
					if dt > 0 {
						rate := (c - s.lastCounter[idx]) / dt
						if rate < 0 {
							rate = 0
						}
						proxy := rate * 0.001
						if proxy > 1 {
							proxy = 1
						}
						sumRate += proxy
						rateN++
					}
				}
				if idx < maxSeriesSlots {
					s.lastCounter[idx] = c
					s.haveCounter[idx] = true
				}
			}
		}
	}
	s.lastAt = now

	if meanN > 0 {
		return sumMean / float64(meanN), nil
	}
	if rateN > 0 {
		return sumRate / float64(rateN), nil
	}
	if !anyOK {
		if lastErr != nil {
			return 0, lastErr
		}
		return 0, fmt.Errorf("forecaster: no scrape targets succeeded")
	}
	return 0, fmt.Errorf("forecaster: no matching series in scrape")
}

// ParseBody is the zero-alloc hot path: aggregate latency proxy from exposition bytes.
// prefixes are exact histogram base names (e.g. softirq_wait_seconds).
func (s *Scraper) ParseBody(body []byte, prefixes [][]byte) (float64, bool) {
	var sumMean float64
	meanN := 0
	for _, p := range prefixes {
		if m, ok := s.histogramMean(body, p); ok {
			sumMean += m
			meanN++
		}
	}
	if meanN == 0 {
		return 0, false
	}
	return sumMean / float64(meanN), true
}

func (s *Scraper) fetch(url string) ([]byte, error) {
	resp, err := s.client.Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("status %d", resp.StatusCode)
	}
	n, err := io.ReadFull(io.LimitReader(resp.Body, int64(len(s.readBuf))), s.readBuf)
	if err == io.ErrUnexpectedEOF || err == io.EOF {
		err = nil
	}
	if err != nil && n == 0 {
		return nil, err
	}
	s.body = append(s.body[:0], s.readBuf[:n]...)
	return s.body, nil
}

func (s *Scraper) histogramMean(body, prefix []byte) (float64, bool) {
	sumName := append(s.sumScratch[:0], prefix...)
	sumName = append(sumName, '_', 's', 'u', 'm')
	countName := append(s.countScratch[:0], prefix...)
	countName = append(countName, '_', 'c', 'o', 'u', 'n', 't')
	sum, ok1 := findMetricValueBytes(body, sumName)
	count, ok2 := findMetricValueBytes(body, countName)
	if !ok1 || !ok2 || count <= 0 {
		return 0, false
	}
	return sum / count, true
}

// ParseExposition walks body once without splitting (0 alloc when names compared as bytes).
func findMetricValueBytes(body, exactName []byte) (float64, bool) {
	var total float64
	found := false
	forEachMetricLine(body, func(name []byte, val float64) {
		if bytesEqual(name, exactName) {
			total += val
			found = true
		}
	})
	return total, found
}

func counterTotalBytes(body, prefix []byte) (float64, bool) {
	var total float64
	found := false
	forEachMetricLine(body, func(name []byte, val float64) {
		if bytesEqual(name, prefix) || bytesHasPrefix(name, prefix) {
			total += val
			found = true
		}
	})
	return total, found
}

func forEachMetricLine(body []byte, fn func(name []byte, val float64)) {
	start := 0
	for i := 0; i <= len(body); i++ {
		if i < len(body) && body[i] != '\n' {
			continue
		}
		line := body[start:i]
		start = i + 1
		if len(line) == 0 || line[0] == '#' {
			continue
		}
		name, val, ok := parseMetricLineBytes(line)
		if !ok {
			continue
		}
		fn(name, val)
	}
}

// parseMetricLineBytes returns name as a subslice of line (no alloc) and parsed value.
func parseMetricLineBytes(line []byte) (name []byte, value float64, ok bool) {
	// trim CR
	if len(line) > 0 && line[len(line)-1] == '\r' {
		line = line[:len(line)-1]
	}
	space := lastIndexByte(line, ' ')
	if space <= 0 {
		return nil, 0, false
	}
	valBytes := trimSpaceLeft(line[space+1:])
	// strip timestamp / exemplar: first token only
	if sp := indexByte(valBytes, ' '); sp >= 0 {
		valBytes = valBytes[:sp]
	}
	v, ok := parseFloatBytes(valBytes)
	if !ok {
		return nil, 0, false
	}
	meta := trimSpaceRight(line[:space])
	brace := indexByte(meta, '{')
	if brace >= 0 {
		name = meta[:brace]
	} else {
		name = meta
	}
	if len(name) == 0 {
		return nil, 0, false
	}
	return name, v, true
}

func bytesEqual(a, b []byte) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

func bytesHasPrefix(b, prefix []byte) bool {
	if len(b) < len(prefix) {
		return false
	}
	return bytesEqual(b[:len(prefix)], prefix)
}

func lastIndexByte(b []byte, c byte) int {
	for i := len(b) - 1; i >= 0; i-- {
		if b[i] == c {
			return i
		}
	}
	return -1
}

func indexByte(b []byte, c byte) int {
	for i := range b {
		if b[i] == c {
			return i
		}
	}
	return -1
}

func trimSpaceLeft(b []byte) []byte {
	for len(b) > 0 && (b[0] == ' ' || b[0] == '\t') {
		b = b[1:]
	}
	return b
}

func trimSpaceRight(b []byte) []byte {
	for len(b) > 0 && (b[len(b)-1] == ' ' || b[len(b)-1] == '\t') {
		b = b[:len(b)-1]
	}
	return b
}

func parseFloatBytes(b []byte) (float64, bool) {
	if len(b) == 0 {
		return 0, false
	}
	sign := 1.0
	i := 0
	if b[0] == '+' {
		i++
	} else if b[0] == '-' {
		sign = -1
		i++
	}
	if i >= len(b) {
		return 0, false
	}
	// special NaN/Inf skipped — metrics are numeric
	var intPart float64
	haveDigit := false
	for i < len(b) && b[i] >= '0' && b[i] <= '9' {
		haveDigit = true
		intPart = intPart*10 + float64(b[i]-'0')
		i++
	}
	var frac float64
	var div float64 = 1
	if i < len(b) && b[i] == '.' {
		i++
		for i < len(b) && b[i] >= '0' && b[i] <= '9' {
			haveDigit = true
			div *= 10
			frac = frac*10 + float64(b[i]-'0')
			i++
		}
	}
	if !haveDigit {
		return 0, false
	}
	val := sign * (intPart + frac/div)
	if i < len(b) && (b[i] == 'e' || b[i] == 'E') {
		i++
		esign := 1
		if i < len(b) && b[i] == '+' {
			i++
		} else if i < len(b) && b[i] == '-' {
			esign = -1
			i++
		}
		exp := 0
		haveE := false
		for i < len(b) && b[i] >= '0' && b[i] <= '9' {
			haveE = true
			exp = exp*10 + int(b[i]-'0')
			i++
		}
		if !haveE {
			return 0, false
		}
		pow := 1.0
		for k := 0; k < exp; k++ {
			pow *= 10
		}
		if esign < 0 {
			val /= pow
		} else {
			val *= pow
		}
	}
	return val, true
}

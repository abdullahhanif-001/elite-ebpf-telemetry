package proctcpsummary

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"strconv"
	"sync"
	"time"

	"github.com/alibaba/kubeskoop/pkg/exporter/probe"
	log "github.com/sirupsen/logrus"

	"github.com/alibaba/kubeskoop/pkg/exporter/nettop"
)

const (
	ModuleName = "proctcpsummary"

	TCPEstablishedConn = "tcpestablishedconn"
	TCPTimeWaitConn    = "tcptimewaitconn"
	TCPCloseWaitConn   = "tcpclosewaitconn"
	TCPSynSentConn     = "tcpsynsentconn"
	TCPSynRecvConn     = "tcpsynrecvconn"
	TCPTXQueue         = "tcptxqueue"
	TCPRXQueue         = "tcprxqueue"
	TCPListenBacklog   = "tcplistenbacklog"

	// st mapping of tcp state
	/*TCPEstablished:1   TCP_SYN_SENT:2
	TCP_SYN_RECV:3      TCP_FIN_WAIT1:4
	TCP_FIN_WAIT2:5     TCPTimewait:6
	TCP_CLOSE:7         TCP_CLOSE_WAIT:8
	TCP_LAST_ACL:9      TCPListen:10
	TCP_CLOSING:11*/

	TCPEstablished = 1
	TCPSynSent     = 2
	TCPSynRecv     = 3
	TCPTimewait    = 6
	TCPCloseWait   = 8
	TCPListen      = 10
)

type tcpSummary struct {
	established uint64
	timeWait    uint64
	closeWait   uint64
	synSent     uint64
	synRecv     uint64
	txQueue     uint64
	rxQueue     uint64
}

func (s *tcpSummary) add(other *tcpSummary) {
	s.established += other.established
	s.timeWait += other.timeWait
	s.closeWait += other.closeWait
	s.synSent += other.synSent
	s.synRecv += other.synRecv
	s.txQueue += other.txQueue
	s.rxQueue += other.rxQueue
}

var (
	TCPSummaryMetrics = []probe.LegacyMetric{
		{Name: TCPEstablishedConn, Help: "The total number of established TCP connections."},
		{Name: TCPTimeWaitConn, Help: "The total number of TCP connections in the TIME_WAIT state."},
		{Name: TCPCloseWaitConn, Help: "The total number of TCP connections in the CLOSE_WAIT state."},
		{Name: TCPSynSentConn, Help: "The total number of TCP connections in the SYN_SENT state."},
		{Name: TCPSynRecvConn, Help: "The total number of TCP connections in the SYN_RECV state."},
		{Name: TCPTXQueue, Help: "The total size of the TCP transmit queue."},
		{Name: TCPRXQueue, Help: "The total size of the TCP receive queue."},
	}

	probeName = "tcpsummary"

	collectCacheTTL = 2 * time.Second
)

// collectCache caches the result of collect() to avoid re-reading all
// /proc/net/tcp files on every Prometheus scrape. The kernel generates
// proc file content on each read by iterating the TCP hash table, so
// reading 118 files per second is expensive. With a 2s TTL, rapid scrapes
// (e.g. 1s interval) reuse cached results.
type collectCache struct {
	mu     sync.Mutex
	result map[string]map[uint32]uint64
	last   time.Time
}

var tcpCache = &collectCache{}

func (c *collectCache) get() (map[string]map[uint32]uint64, error) {
	c.mu.Lock()
	defer c.mu.Unlock()

	if time.Since(c.last) > collectCacheTTL {
		ets := nettop.GetAllUniqueNetnsEntity()
		if len(ets) == 0 {
			log.Infof("failed collect tcp summary, no entity found")
		}

		sockDiagOnce.Do(probeSockDiagSupport)
		if useSockDiag {
			c.result = collectSockDiag(ets)
		} else {
			log.Debugf("sock_diag unavailable (%v), using proc", useSockDiagErr)
			c.result = collect(ets)
		}
		c.last = time.Now()
	}

	return c.result, nil
}

func init() {
	probe.MustRegisterMetricsProbe(probeName, softNetProbeCreator)
}

func softNetProbeCreator() (probe.MetricsProbe, error) {
	p := &ProcTCP{}

	batchMetrics := probe.NewLegacyBatchMetrics(probeName, TCPSummaryMetrics, p.CollectOnce)

	return probe.NewMetricsProbe(probeName, p, batchMetrics), nil
}

type ProcTCP struct {
}

func (s *ProcTCP) Start(_ context.Context) error {
	return nil
}

func (s *ProcTCP) Stop(_ context.Context) error {
	return nil
}

func (s *ProcTCP) CollectOnce() (map[string]map[uint32]uint64, error) {
	return tcpCache.get()
}

// CollectSnapshot returns cached TCP summary metrics for all pod netns.
// Used by connecttrace and other physics-layer probes.
func CollectSnapshot() (map[string]map[uint32]uint64, error) {
	return tcpCache.get()
}

func collect(pidlist []*nettop.Entity) map[string]map[uint32]uint64 {
	resMap := make(map[string]map[uint32]uint64)

	for idx := range TCPSummaryMetrics {
		resMap[TCPSummaryMetrics[idx].Name] = map[uint32]uint64{}
	}

	for idx := range pidlist {
		pid := pidlist[idx].GetPid()
		nsinum := uint32(pidlist[idx].GetNetns())

		var combined tcpSummary
		for _, proto := range []string{"tcp", "tcp6"} {
			path := fmt.Sprintf("/proc/%d/net/%s", pid, proto)
			s, err := collectTCPSummary(path)
			if err != nil {
				log.Warnf("failed collect %s, path %s, err: %v", proto, path, err)
				continue
			}
			combined.add(&s)
		}

		resMap[TCPEstablishedConn][nsinum] = combined.established
		resMap[TCPTimeWaitConn][nsinum] = combined.timeWait
		resMap[TCPCloseWaitConn][nsinum] = combined.closeWait
		resMap[TCPSynSentConn][nsinum] = combined.synSent
		resMap[TCPSynRecvConn][nsinum] = combined.synRecv
		resMap[TCPTXQueue][nsinum] = combined.txQueue
		resMap[TCPRXQueue][nsinum] = combined.rxQueue
	}

	return resMap
}

// collectTCPSummary reads a /proc/{pid}/net/tcp{,6} file and accumulates
// state counts and queue lengths in a single pass. Only fields 3 (st) and
// 4 (tx_queue:rx_queue) are parsed; IP addresses, ports, UID, and inode
// are skipped entirely to avoid unnecessary allocations and CPU.
func collectTCPSummary(file string) (tcpSummary, error) {
	var s tcpSummary
	f, err := os.Open(file)
	if err != nil {
		return s, err
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	scanner.Scan() // skip header line
	for scanner.Scan() {
		line := scanner.Text()
		st, txq, rxq, err := parseStAndQueues(line)
		if err != nil {
			continue // skip malformed lines
		}
		switch st {
		case TCPEstablished:
			s.established++
		case TCPTimewait:
			s.timeWait++
		case TCPCloseWait:
			s.closeWait++
		case TCPSynSent:
			s.synSent++
		case TCPSynRecv:
			s.synRecv++
		}
		if st != TCPListen {
			s.txQueue += txq
			s.rxQueue += rxq
		}
	}
	return s, scanner.Err()
}

// parseStAndQueues extracts the st (field 3) and tx_queue:rx_queue (field 4)
// from a /proc/net/tcp line by index-based scanning, without allocating
// intermediate slices or strings.
//
// /proc/net/tcp line format:
//
//	sl  local_address rem_address   st tx_queue:rx_queue ...
//	0:  0100007F:1F90 00000000:0000 0A 00000000:00000000 00:00000000 ...
//
// Fields are separated by whitespace. We skip to field 3 (st) and field 4
// (tx_queue:rx_queue) using manual index advancement.
func parseStAndQueues(line string) (st, txq, rxq uint64, err error) {
	n := len(line)
	i := 0

	// Skip 3 fields (sl, local_address, rem_address) to reach st (field 3)
	for field := 0; field < 3; field++ {
		// skip leading whitespace
		for i < n && (line[i] == ' ' || line[i] == '\t') {
			i++
		}
		// skip field content
		for i < n && line[i] != ' ' && line[i] != '\t' {
			i++
		}
	}

	// skip whitespace before st field
	for i < n && (line[i] == ' ' || line[i] == '\t') {
		i++
	}
	// extract st (hex)
	start := i
	for i < n && line[i] != ' ' && line[i] != '\t' {
		i++
	}
	if start == i {
		return 0, 0, 0, fmt.Errorf("missing st field")
	}
	st, err = strconv.ParseUint(line[start:i], 16, 64)
	if err != nil {
		return 0, 0, 0, err
	}

	// skip whitespace before tx_queue:rx_queue field
	for i < n && (line[i] == ' ' || line[i] == '\t') {
		i++
	}
	// extract tx_queue (hex, before ':')
	start = i
	for i < n && line[i] != ':' {
		i++
	}
	if i >= n {
		return 0, 0, 0, fmt.Errorf("missing queue field")
	}
	txq, err = strconv.ParseUint(line[start:i], 16, 64)
	if err != nil {
		return 0, 0, 0, err
	}
	// skip ':'
	i++
	// extract rx_queue (hex, until whitespace)
	start = i
	for i < n && line[i] != ' ' && line[i] != '\t' {
		i++
	}
	if start == i {
		return 0, 0, 0, fmt.Errorf("missing rx_queue field")
	}
	rxq, err = strconv.ParseUint(line[start:i], 16, 64)
	if err != nil {
		return 0, 0, 0, err
	}

	return st, txq, rxq, nil
}

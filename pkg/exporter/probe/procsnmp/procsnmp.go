package procsnmp

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/alibaba/kubeskoop/pkg/exporter/nettop"
	"github.com/alibaba/kubeskoop/pkg/exporter/probe"
	log "github.com/sirupsen/logrus"
)

const (
	ProtocolICMP     = "Icmp"
	ProtocolICMPMsg  = "IcmpMsg"
	ProtocolIP       = "Ip"
	ProtocolIPExt    = "IpExt"
	ProtocolMPTCPExt = "MPTcpExt"
	ProtocolTCP      = "Tcp"
	ProtocolTCPExt   = "TcpExt"
	ProtocolUDP      = "Udp"
	ProtocolUDPLite  = "UdpLite"

	// metrics of tcp
	TCPActiveOpens     = "activeopens"
	TCPPassiveOpens    = "passiveopens"
	TCPRetransSegs     = "retranssegs"
	TCPListenDrops     = "listendrops"
	TCPListenOverflows = "listenoverflows"
	TCPSynRetrans      = "tcpsynretrans"
	TCPFastRetrans     = "tcpfastretrans"
	TCPRetransFail     = "tcpretransfail"
	TCPTimeouts        = "tcptimeouts"
	TCPAttemptFails    = "attemptfails"
	TCPEstabResets     = "estabresets"
	TCPCurrEstab       = "currestab"
	TCPInSegs          = "insegs"
	TCPOutSegs         = "outsegs"
	TCPInErrs          = "inerrs"
	TCPOutRsts         = "outrsts"

	// metrics of udp
	UDPInDatagrams  = "indatagrams"
	UDPNoPorts      = "noports"
	UDPInErrors     = "inerrors"
	UDPOutDatagrams = "outdatagrams"
	UDPRcvbufErrors = "rcvbuferrors"
	UDPSndbufErrors = "sndbuferrors"
	UDPInCsumErrors = "incsumerrors"
	UDPIgnoredMulti = "ignoredmulti"

	//metrics of ip
	IPForwarding      = "forwarding"
	IPDefaultTTL      = "defaultttl"
	IPInReceives      = "inreceives"
	IPInHdrErrors     = "inhdrerrors"
	IPInAddrErrors    = "inaddrerrors"
	IPForwDatagrams   = "forwdatagrams"
	IPInUnknownProtos = "inunknownprotos"
	IPInDiscards      = "indiscards"
	IPInDelivers      = "indelivers"
	IPOutRequests     = "outrequests"
	IPOutDiscards     = "outdiscards"
	IPOutNoRoutes     = "outnoroutes"
	IPReasmTimeout    = "reasmtimeout"
	IPReasmReqds      = "reasmreqds"
	IPReasmOKs        = "reasmoks"
	IPReasmFails      = "reasmfails"
	IPFragOKs         = "fragoks"
	IPFragFails       = "fragfails"
	IPFragCreates     = "fragcreates"

	TCP = "tcp"
	UDP = "udp"
	IP  = "ip"
)

var (
	TCPStatMetrcis = []probe.LegacyMetric{
		{Name: TCPActiveOpens, Help: "The number of active TCP connections opened."},
		{Name: TCPPassiveOpens, Help: "The number of passive TCP connections opened (i.e., connections established by accepting incoming connections)."},
		{Name: TCPRetransSegs, Help: "The total number of segments that have been retransmitted."},
		{Name: TCPAttemptFails, Help: "The number of failed attempts to establish a TCP connection."},
		{Name: TCPEstabResets, Help: "The number of established TCP connections that were reset."},
		{Name: TCPCurrEstab, Help: "The current number of established TCP connections."},
		{Name: TCPInSegs, Help: "The total number of TCP segments received."},
		{Name: TCPOutSegs, Help: "The total number of TCP segments sent."},
		{Name: TCPInErrs, Help: "The total number of erroneous packets received on TCP."},
		{Name: TCPOutRsts, Help: "The total number of TCP segments sent with the RST flag set."},
	}

	UDPStatMetrics = []probe.LegacyMetric{
		{Name: UDPInDatagrams, Help: "The total number of UDP datagrams received."},
		{Name: UDPNoPorts, Help: "The total number of UDP datagrams received for which there was no port at the destination."},
		{Name: UDPInErrors, Help: "The total number of erroneous received UDP packets."},
		{Name: UDPOutDatagrams, Help: "The total number of UDP datagrams sent."},
		{Name: UDPRcvbufErrors, Help: "The total number of UDP datagrams dropped due to socket receive buffer errors."},
		{Name: UDPSndbufErrors, Help: "The total number of UDP datagrams dropped due to socket send buffer errors."},
		{Name: UDPInCsumErrors, Help: "The total number of UDP datagrams received with a checksum error."},
		{Name: UDPIgnoredMulti, Help: "The total number of received UDP multicast packets that were ignored."},
	}

	IPMetrics = []probe.LegacyMetric{
		{Name: IPForwarding, Help: "Indicates whether IP forwarding is enabled (1 for enabled, 0 for disabled)."},
		{Name: IPDefaultTTL, Help: "The default time-to-live (TTL) value for IP packets."},
		{Name: IPInReceives, Help: "The total number of IP packets received."},
		{Name: IPInHdrErrors, Help: "The total number of received IP packets that had a header error."},
		{Name: IPInAddrErrors, Help: "The total number of received IP packets that were discarded due to address errors."},
		{Name: IPForwDatagrams, Help: "The total number of IP packets forwarded by this machine."},
		{Name: IPInUnknownProtos, Help: "The total number of received IP packets for which the protocol is not known."},
		{Name: IPInDiscards, Help: "The total number of received IP packets that were discarded."},
		{Name: IPInDelivers, Help: "The total number of delivered IP packets."},
		{Name: IPOutRequests, Help: "The total number of IP packets sent out."},
		{Name: IPOutDiscards, Help: "The total number of outgoing IP packets that were discarded."},
		{Name: IPOutNoRoutes, Help: "The total number of outgoing IP packets for which no route could be found."},
		{Name: IPReasmTimeout, Help: "The total number of times that IP reassembly timed out."},
		{Name: IPReasmReqds, Help: "The total number of IP reassembly requests made."},
		{Name: IPReasmOKs, Help: "The total number of successful IP reassembly operations."},
		{Name: IPReasmFails, Help: "The total number of failed IP reassembly operations."},
		{Name: IPFragOKs, Help: "The total number of IP packets that were fragmented successfully."},
		{Name: IPFragFails, Help: "The total number of IP packets that failed to fragment."},
		{Name: IPFragCreates, Help: "The total number of IP fragments created."},
	}

	metricsMap = map[string][]probe.LegacyMetric{
		TCP: TCPStatMetrcis,
		UDP: UDPStatMetrics,
		IP:  IPMetrics,
	}

	cache = &snmpCache{
		cache: make(map[string]map[string]map[uint32]uint64),
	}

	// wantedSnmpFields: lowercase protocol -> lowercase field name -> (proto key, metric name).
	// Built once at init to avoid per-call allocations.
	wantedSnmpFields map[string]map[string]wantedField
)

type wantedField struct {
	protoKey   string
	metricName string
}

func init() {
	// Build the lookup table once.
	wantedSnmpFields = make(map[string]map[string]wantedField)
	for protoKey, metricsList := range metricsMap {
		for _, m := range metricsList {
			// /proc/net/snmp uses "Tcp", "Udp", "Ip" as protocol prefix.
			// After lowercasing, "tcp" maps to protoKey "tcp", etc.
			if wantedSnmpFields[protoKey] == nil {
				wantedSnmpFields[protoKey] = make(map[string]wantedField)
			}
			wantedSnmpFields[protoKey][m.Name] = wantedField{protoKey: protoKey, metricName: m.Name}
		}
	}

	probe.MustRegisterMetricsProbe(TCP, newSnmpProbeCreator(TCP))
	probe.MustRegisterMetricsProbe(UDP, newSnmpProbeCreator(UDP))
	probe.MustRegisterMetricsProbe(IP, newSnmpProbeCreator(IP))
}

func newSnmpProbeCreator(probeName string) func() (probe.MetricsProbe, error) {
	return func() (probe.MetricsProbe, error) {
		p := &procSNMP{
			name: probeName,
		}
		metrics := metricsMap[probeName]
		batchMetrics := probe.NewLegacyBatchMetrics(probeName, metrics, p.CollectOnce)
		return probe.NewMetricsProbe(probeName, p, batchMetrics), nil
	}
}

type procSNMP struct {
	name string
}

func (s *procSNMP) Start(_ context.Context) error {
	return nil
}

func (s *procSNMP) Stop(_ context.Context) error {
	return nil
}

func (s *procSNMP) CollectOnce() (map[string]map[uint32]uint64, error) {
	return cache.get(s.name)
}

type snmpCache struct {
	cache map[string]map[string]map[uint32]uint64
	err   error
	last  time.Time
	lock  sync.Mutex
}

func (c *snmpCache) get(name string) (map[string]map[uint32]uint64, error) {
	c.lock.Lock()
	defer c.lock.Unlock()

	if c.err != nil {
		return nil, c.err
	}

	if time.Since(c.last) > time.Second*2 {
		c.reload()
	}

	return c.cache[name], nil
}

func (c *snmpCache) reload() {
	c.cache, c.err = collect()
	c.last = time.Now()
}

func collect() (map[string]map[string]map[uint32]uint64, error) {
	entitys := nettop.GetAllUniqueNetnsEntity()

	res := make(map[string]map[string]map[uint32]uint64)

	for proto, metricsList := range metricsMap {
		res[proto] = make(map[string]map[uint32]uint64)
		for _, metrics := range metricsList {
			res[proto][metrics.Name] = make(map[uint32]uint64)
		}
	}

	for _, et := range entitys {
		if et != nil {
			pid := et.GetPid()
			nsinum := uint32(et.GetNetns())
			snmppath := fmt.Sprintf("/proc/%d/net/snmp", pid)
			if err := parseSnmpDirect(snmppath, nsinum, res); err != nil {
				log.Errorf("snmp failed collect pid %d, nsinum %d, err: %v", pid, nsinum, err)
			}
		}
	}

	return res, nil
}

// parseSnmpDirect reads /proc/<pid>/net/snmp and writes wanted metrics
// directly into res, avoiding intermediate map[string]map[string]string allocations.
func parseSnmpDirect(path string, nsinum uint32, res map[string]map[string]map[uint32]uint64) error {
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		headerLine := scanner.Text()
		if !scanner.Scan() {
			break
		}
		valueLine := scanner.Text()

		colonIdx := strings.IndexByte(headerLine, ':')
		if colonIdx < 0 {
			continue
		}
		protocol := strings.ToLower(headerLine[:colonIdx])

		protoFields, ok := wantedSnmpFields[protocol]
		if !ok {
			continue
		}

		hi := colonIdx + 1
		vi := strings.IndexByte(valueLine, ':')
		if vi < 0 {
			continue
		}
		vi++

		hLen := len(headerLine)
		vLen := len(valueLine)

		for {
			for hi < hLen && headerLine[hi] == ' ' {
				hi++
			}
			if hi >= hLen {
				break
			}
			hStart := hi
			for hi < hLen && headerLine[hi] != ' ' {
				hi++
			}
			fieldName := strings.ToLower(headerLine[hStart:hi])

			for vi < vLen && valueLine[vi] == ' ' {
				vi++
			}
			vStart := vi
			for vi < vLen && valueLine[vi] != ' ' {
				vi++
			}

			if wf, ok := protoFields[fieldName]; ok {
				if vStart < vi {
					val, err := strconv.ParseInt(valueLine[vStart:vi], 10, 64)
					if err == nil {
						res[wf.protoKey][wf.metricName][nsinum] = uint64(val)
					}
				}
			}
		}
	}

	return scanner.Err()
}

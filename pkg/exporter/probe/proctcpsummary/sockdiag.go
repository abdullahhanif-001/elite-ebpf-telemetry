package proctcpsummary

import (
	"fmt"
	"sync"
	"syscall"

	"github.com/alibaba/kubeskoop/pkg/exporter/nettop"
	"github.com/mdlayher/netlink"
	"github.com/mdlayher/netlink/nlenc"
	log "github.com/sirupsen/logrus"
)

const (
	// NETLINK_SOCK_DIAG is the netlink protocol for socket diagnostics.
	netlinkSockDiag = 4

	// SOCK_DIAG_BY_FAMILY is the netlink message type for inet_diag_req_v2.
	sockDiagByFamily = 20

	// Size of inet_diag_req_v2 struct.
	inetDiagReqV2Size = 56

	// Minimum size of inet_diag_msg response struct.
	inetDiagMsgSize = 72

	// Offsets within inet_diag_msg.
	offsetState  = 1  // idiag_state (uint8)
	offsetRQueue = 56 // idiag_rqueue (uint32, native endian)
	offsetWQueue = 60 // idiag_wqueue (uint32, native endian)

	// allTCPStates is a bitmask for all TCP states (1-11).
	allTCPStates = 0xFFF
)

var (
	sockDiagOnce   sync.Once
	useSockDiag    bool
	useSockDiagErr error
)

// probeSockDiagSupport tests whether NETLINK_SOCK_DIAG is available by
// attempting a minimal query in the current (host) namespace.
func probeSockDiagSupport() {
	conn, err := netlink.Dial(netlinkSockDiag, nil)
	if err != nil {
		useSockDiag = false
		useSockDiagErr = err
		return
	}
	defer conn.Close()

	req := netlink.Message{
		Header: netlink.Header{
			Type:  sockDiagByFamily,
			Flags: netlink.Request | netlink.Dump,
		},
		Data: buildInetDiagReq(syscall.AF_INET),
	}
	_, err = conn.Execute(req)
	if err != nil {
		useSockDiag = false
		useSockDiagErr = err
		return
	}
	useSockDiag = true
}

// collectSockDiag collects TCP summary metrics for all entities using
// NETLINK_SOCK_DIAG. It has the same return type as collect() (proc-based).
func collectSockDiag(entities []*nettop.Entity) map[string]map[uint32]uint64 {
	resMap := make(map[string]map[uint32]uint64)
	for idx := range TCPSummaryMetrics {
		resMap[TCPSummaryMetrics[idx].Name] = map[uint32]uint64{}
	}

	for _, et := range entities {
		nsinum := uint32(et.GetNetns())
		combined, err := collectSockDiagForEntity(et)
		if err != nil {
			log.Warnf("failed collect sock_diag for netns %d: %v", nsinum, err)
			continue
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

// collectSockDiagForEntity queries TCP socket state for a single network
// namespace via NETLINK_SOCK_DIAG. It opens a netlink connection in the
// entity's namespace, sends AF_INET and AF_INET6 dump requests, and
// parses the binary responses.
func collectSockDiagForEntity(entity *nettop.Entity) (tcpSummary, error) {
	nsHandle, err := entity.OpenNsHandle()
	if err != nil {
		return tcpSummary{}, fmt.Errorf("open ns handle: %w", err)
	}
	defer nsHandle.Close()

	conn, err := netlink.Dial(netlinkSockDiag, &netlink.Config{
		NetNS: int(nsHandle),
	})
	if err != nil {
		return tcpSummary{}, fmt.Errorf("dial sock_diag: %w", err)
	}
	defer conn.Close()

	var combined tcpSummary
	for _, family := range []uint8{syscall.AF_INET, syscall.AF_INET6} {
		req := netlink.Message{
			Header: netlink.Header{
				Type:  sockDiagByFamily,
				Flags: netlink.Request | netlink.Dump,
			},
			Data: buildInetDiagReq(family),
		}
		msgs, err := conn.Execute(req)
		if err != nil {
			return tcpSummary{}, fmt.Errorf("execute sock_diag family %d: %w", family, err)
		}
		partial := parseDiagMsgs(msgs)
		combined.add(&partial)
	}

	return combined, nil
}

// buildInetDiagReq builds a 56-byte inet_diag_req_v2 payload.
//
// Layout:
//
//	[0]   sdiag_family   = family (AF_INET or AF_INET6)
//	[1]   sdiag_protocol = IPPROTO_TCP (6)
//	[2]   idiag_ext      = 0 (no extensions)
//	[3]   pad            = 0
//	[4:8] idiag_states   = allTCPStates (native endian)
//	[8:56] inet_diag_sockid = zeroed (dump all sockets)
func buildInetDiagReq(family uint8) []byte {
	data := make([]byte, inetDiagReqV2Size)
	data[0] = family
	data[1] = syscall.IPPROTO_TCP
	nlenc.PutUint32(data[4:8], allTCPStates)
	return data
}

// parseDiagMsgs extracts TCP state counts and queue lengths from a slice
// of inet_diag_msg responses. Only 3 fields are read per message:
// idiag_state (offset 1), idiag_rqueue (offset 56), idiag_wqueue (offset 60).
func parseDiagMsgs(msgs []netlink.Message) tcpSummary {
	var s tcpSummary
	for _, msg := range msgs {
		if len(msg.Data) < inetDiagMsgSize {
			continue
		}
		state := msg.Data[offsetState]
		rqueue := nlenc.Uint32(msg.Data[offsetRQueue : offsetRQueue+4])
		wqueue := nlenc.Uint32(msg.Data[offsetWQueue : offsetWQueue+4])

		switch uint64(state) {
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
		if uint64(state) != TCPListen {
			s.txQueue += uint64(wqueue)
			s.rxQueue += uint64(rqueue)
		}
	}
	return s
}

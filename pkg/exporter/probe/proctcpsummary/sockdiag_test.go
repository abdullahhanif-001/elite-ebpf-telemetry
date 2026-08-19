package proctcpsummary

import (
	"syscall"
	"testing"

	"github.com/mdlayher/netlink"
	"github.com/mdlayher/netlink/nlenc"
)

func TestBuildInetDiagReq(t *testing.T) {
	tests := []struct {
		name       string
		family     uint8
		wantFamily uint8
		wantProto  uint8
		wantStates uint32
	}{
		{
			name:       "AF_INET",
			family:     syscall.AF_INET,
			wantFamily: syscall.AF_INET,
			wantProto:  syscall.IPPROTO_TCP,
			wantStates: allTCPStates,
		},
		{
			name:       "AF_INET6",
			family:     syscall.AF_INET6,
			wantFamily: syscall.AF_INET6,
			wantProto:  syscall.IPPROTO_TCP,
			wantStates: allTCPStates,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			data := buildInetDiagReq(tt.family)
			if len(data) != inetDiagReqV2Size {
				t.Fatalf("size = %d, want %d", len(data), inetDiagReqV2Size)
			}
			if data[0] != tt.wantFamily {
				t.Errorf("family = %d, want %d", data[0], tt.wantFamily)
			}
			if data[1] != tt.wantProto {
				t.Errorf("protocol = %d, want %d", data[1], tt.wantProto)
			}
			if data[2] != 0 {
				t.Errorf("idiag_ext = %d, want 0", data[2])
			}
			gotStates := nlenc.Uint32(data[4:8])
			if gotStates != tt.wantStates {
				t.Errorf("states = 0x%x, want 0x%x", gotStates, tt.wantStates)
			}
		})
	}
}

// buildTestDiagMsg creates a minimal 72-byte inet_diag_msg for testing.
func buildTestDiagMsg(family, state uint8, rqueue, wqueue uint32) []byte {
	data := make([]byte, inetDiagMsgSize)
	data[0] = family
	data[1] = state
	nlenc.PutUint32(data[offsetRQueue:offsetRQueue+4], rqueue)
	nlenc.PutUint32(data[offsetWQueue:offsetWQueue+4], wqueue)
	return data
}

func TestParseDiagMsgs(t *testing.T) {
	msgs := []netlink.Message{
		// 2 ESTABLISHED connections with queues
		{Data: buildTestDiagMsg(syscall.AF_INET, TCPEstablished, 100, 200)},
		{Data: buildTestDiagMsg(syscall.AF_INET, TCPEstablished, 50, 30)},
		// 1 TIME_WAIT
		{Data: buildTestDiagMsg(syscall.AF_INET, TCPTimewait, 0, 0)},
		// 1 CLOSE_WAIT with queues
		{Data: buildTestDiagMsg(syscall.AF_INET, TCPCloseWait, 10, 20)},
		// 1 SYN_SENT
		{Data: buildTestDiagMsg(syscall.AF_INET, TCPSynSent, 0, 0)},
		// 1 SYN_RECV
		{Data: buildTestDiagMsg(syscall.AF_INET, TCPSynRecv, 0, 0)},
		// 1 LISTEN (queues should be excluded)
		{Data: buildTestDiagMsg(syscall.AF_INET, TCPListen, 0, 5)},
		// 1 short message (should be skipped)
		{Data: make([]byte, 10)},
	}

	s := parseDiagMsgs(msgs)

	if s.established != 2 {
		t.Errorf("established = %d, want 2", s.established)
	}
	if s.timeWait != 1 {
		t.Errorf("timeWait = %d, want 1", s.timeWait)
	}
	if s.closeWait != 1 {
		t.Errorf("closeWait = %d, want 1", s.closeWait)
	}
	if s.synSent != 1 {
		t.Errorf("synSent = %d, want 1", s.synSent)
	}
	if s.synRecv != 1 {
		t.Errorf("synRecv = %d, want 1", s.synRecv)
	}
	// rxQueue: 100 + 50 + 0 + 10 + 0 + 0 = 160 (LISTEN excluded)
	if s.rxQueue != 160 {
		t.Errorf("rxQueue = %d, want 160", s.rxQueue)
	}
	// txQueue: 200 + 30 + 0 + 20 + 0 + 0 = 250 (LISTEN excluded)
	if s.txQueue != 250 {
		t.Errorf("txQueue = %d, want 250", s.txQueue)
	}
}

func TestParseDiagMsgsEmpty(t *testing.T) {
	s := parseDiagMsgs(nil)
	if s.established != 0 || s.timeWait != 0 || s.txQueue != 0 || s.rxQueue != 0 {
		t.Errorf("expected zero summary for nil input, got %+v", s)
	}
}

func BenchmarkParseDiagMsgs(b *testing.B) {
	// Build 50 messages simulating a realistic namespace
	msgs := make([]netlink.Message, 50)
	for i := range msgs {
		var state uint8
		switch i % 5 {
		case 0:
			state = TCPEstablished
		case 1:
			state = TCPTimewait
		case 2:
			state = TCPCloseWait
		case 3:
			state = TCPListen
		case 4:
			state = TCPSynSent
		}
		msgs[i] = netlink.Message{Data: buildTestDiagMsg(syscall.AF_INET, state, uint32(i*10), uint32(i*5))}
	}

	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		parseDiagMsgs(msgs)
	}
}

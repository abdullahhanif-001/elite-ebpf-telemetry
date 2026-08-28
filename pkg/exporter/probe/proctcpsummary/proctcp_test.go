package proctcpsummary

import (
	"os"
	"path/filepath"
	"testing"
)

func TestParseStAndQueues(t *testing.T) {
	tests := []struct {
		name    string
		line    string
		wantSt  uint64
		wantTxq uint64
		wantRxq uint64
		wantErr bool
	}{
		{
			name:    "established connection",
			line:    "   0: 0100007F:1F90 00000000:0000 01 00000000:00000000 00:00000000 00000000     0        0 12345 1 0000000000000000 100 0 0 10 0",
			wantSt:  1, // TCPEstablished
			wantTxq: 0,
			wantRxq: 0,
		},
		{
			name:    "time_wait connection",
			line:    "   1: 0100007F:1F90 0100007F:CEA4 06 00000000:00000000 03:000008BB 00000000     0        0 0 3 0000000000000000",
			wantSt:  6, // TCPTimewait
			wantTxq: 0,
			wantRxq: 0,
		},
		{
			name:    "connection with queues",
			line:    "  10: 0100007F:1F90 0100007F:CEA4 01 00000100:00000200 00:00000000 00000000  1000        0 54321 1 0000000000000000 100 0 0 10 0",
			wantSt:  1,
			wantTxq: 0x100,
			wantRxq: 0x200,
		},
		{
			name:    "listen socket",
			line:    "   5: 00000000:0050 00000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 99999 1 0000000000000000 100 0 0 10 0",
			wantSt:  0x0A, // TCPListen
			wantTxq: 0,
			wantRxq: 0,
		},
		{
			name:    "close_wait connection",
			line:    "   3: AC1F0064:ABCD EF012345:0050 08 00000010:00000020 00:00000000 00000000   100        0 12345 1 0000000000000000 100 0 0 10 0",
			wantSt:  8, // TCPCloseWait
			wantTxq: 0x10,
			wantRxq: 0x20,
		},
		{
			name:    "syn_sent connection",
			line:    "   2: AC1F0064:ABCD EF012345:0050 02 00000000:00000000 01:00000E10 00000003   100        0 12345 1 0000000000000000 100 0 0 10 0",
			wantSt:  2, // TCPSynSent
			wantTxq: 0,
			wantRxq: 0,
		},
		{
			name:    "tcp6 line",
			line:    "   0: 00000000000000000000000001000000:0277 00000000000000000000000000000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 15890 1 0000000000000000 100 0 0 10 0",
			wantSt:  0x0A, // TCPListen
			wantTxq: 0,
			wantRxq: 0,
		},
		{
			name:    "too short line",
			line:    "   0: ",
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			st, txq, rxq, err := parseStAndQueues(tt.line)
			if tt.wantErr {
				if err == nil {
					t.Errorf("expected error, got nil")
				}
				return
			}
			if err != nil {
				t.Errorf("unexpected error: %v", err)
				return
			}
			if st != tt.wantSt {
				t.Errorf("st = %d, want %d", st, tt.wantSt)
			}
			if txq != tt.wantTxq {
				t.Errorf("txq = %d, want %d", txq, tt.wantTxq)
			}
			if rxq != tt.wantRxq {
				t.Errorf("rxq = %d, want %d", rxq, tt.wantRxq)
			}
		})
	}
}

func TestCollectTCPSummary(t *testing.T) {
	// Create a temp file simulating /proc/net/tcp
	content := `  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode
   0: 0100007F:1F90 00000000:0000 01 00000000:00000000 00:00000000 00000000     0        0 12345 1 0000000000000000 100 0 0 10 0
   1: 0100007F:1F91 0100007F:CEA4 01 00000010:00000020 00:00000000 00000000     0        0 12346 1 0000000000000000 100 0 0 10 0
   2: 0100007F:1F92 0100007F:CEA5 06 00000000:00000000 03:000008BB 00000000     0        0 0 3 0000000000000000
   3: 0100007F:1F93 0100007F:CEA6 08 00000005:00000003 00:00000000 00000000     0        0 12347 1 0000000000000000 100 0 0 10 0
   4: 0100007F:1F94 0100007F:CEA7 02 00000000:00000000 01:00000E10 00000003     0        0 12348 1 0000000000000000 100 0 0 10 0
   5: 00000000:0050 00000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 99999 1 0000000000000000 100 0 0 10 0
   6: 0100007F:1F95 0100007F:CEA8 03 00000000:00000000 00:00000000 00000000     0        0 12349 1 0000000000000000 100 0 0 10 0
`
	dir := t.TempDir()
	path := filepath.Join(dir, "tcp")
	if err := os.WriteFile(path, []byte(content), 0644); err != nil {
		t.Fatal(err)
	}

	s, err := collectTCPSummary(path)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	// 2 established (lines 0,1)
	if s.established != 2 {
		t.Errorf("established = %d, want 2", s.established)
	}
	// 1 time_wait (line 2)
	if s.timeWait != 1 {
		t.Errorf("timeWait = %d, want 1", s.timeWait)
	}
	// 1 close_wait (line 3)
	if s.closeWait != 1 {
		t.Errorf("closeWait = %d, want 1", s.closeWait)
	}
	// 1 syn_sent (line 4)
	if s.synSent != 1 {
		t.Errorf("synSent = %d, want 1", s.synSent)
	}
	// 1 syn_recv (line 6)
	if s.synRecv != 1 {
		t.Errorf("synRecv = %d, want 1", s.synRecv)
	}
	// tx_queue: 0+0x10+0+0x05+0+0 = 0x15 = 21 (listen excluded)
	if s.txQueue != 0x15 {
		t.Errorf("txQueue = %d, want %d", s.txQueue, 0x15)
	}
	// rx_queue: 0+0x20+0+0x03+0+0 = 0x23 = 35 (listen excluded)
	if s.rxQueue != 0x23 {
		t.Errorf("rxQueue = %d, want %d", s.rxQueue, 0x23)
	}
}

func BenchmarkParseStAndQueues(b *testing.B) {
	line := "   0: 0100007F:1F90 0100007F:CEA4 01 00000100:00000200 00:00000000 00000000  1000        0 54321 1 0000000000000000 100 0 0 10 0"
	b.ReportAllocs()
	for i := 0; i < b.N; i++ {
		_, _, _, _ = parseStAndQueues(line)
	}
}

func BenchmarkCollectTCPSummary(b *testing.B) {
	// Create test file with realistic content
	var lines []byte
	lines = append(lines, []byte("  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode\n")...)
	for i := 0; i < 50; i++ {
		lines = append(lines, []byte("   0: 0100007F:1F90 0100007F:CEA4 01 00000000:00000000 00:00000000 00000000     0        0 12345 1 0000000000000000 100 0 0 10 0\n")...)
	}
	dir := b.TempDir()
	path := filepath.Join(dir, "tcp")
	if err := os.WriteFile(path, lines, 0644); err != nil {
		b.Fatal(err)
	}

	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, _ = collectTCPSummary(path)
	}
}

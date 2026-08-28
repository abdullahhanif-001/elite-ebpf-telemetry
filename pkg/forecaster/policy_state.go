package forecaster

import (
	"encoding/binary"
	"os"
	"path/filepath"
	"sync/atomic"
	"time"
)

const (
	policyMagicStr   = "ELPS"
	policySchemaVer  = uint32(1)
	policyRecordSize = 64
)

var policySeq uint64

// WritePolicyState atomically persists a 64-byte binary policy record.
func WritePolicyState(path string, snap Snapshot) error {
	if path == "" {
		return nil
	}
	_ = os.MkdirAll(filepath.Dir(path), 0o755)

	fault := uint8(0)
	if snap.Fault {
		fault = 1
	}
	rec := make([]byte, policyRecordSize)
	copy(rec[0:4], []byte(policyMagicStr))
	binary.LittleEndian.PutUint32(rec[4:8], policySchemaVer)
	binary.LittleEndian.PutUint64(rec[8:16], atomic.AddUint64(&policySeq, 1))
	rec[16] = fault
	rec[17] = causeToPolicyCode(snap.Cause)
	binary.LittleEndian.PutUint64(rec[24:32], uint64(snap.Projected*1e9))
	binary.LittleEndian.PutUint64(rec[32:40], uint64(snap.EWMA*1e9))
	binary.LittleEndian.PutUint64(rec[40:48], uint64(time.Now().UTC().UnixNano()))

	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, rec, 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

// ReadPolicyState loads the binary policy record written by WritePolicyState.
func ReadPolicyState(path string) (Snapshot, error) {
	var snap Snapshot
	b, err := os.ReadFile(path)
	if err != nil {
		return snap, err
	}
	if len(b) < policyRecordSize {
		return snap, os.ErrInvalid
	}
	if string(b[0:4]) != policyMagicStr {
		return snap, os.ErrInvalid
	}
	snap.Fault = b[16] == 1
	snap.Cause = policyCodeToCause(b[17])
	snap.Projected = float64(binary.LittleEndian.Uint64(b[24:32])) / 1e9
	snap.EWMA = float64(binary.LittleEndian.Uint64(b[32:40])) / 1e9
	return snap, nil
}

func causeToPolicyCode(c string) uint8 {
	switch c {
	case CauseNetwork:
		return 1
	case CauseLLC:
		return 2
	case CausePSI:
		return 3
	case CauseMixed:
		return 4
	default:
		return 0
	}
}

func policyCodeToCause(code uint8) string {
	switch code {
	case 1:
		return CauseNetwork
	case 2:
		return CauseLLC
	case 3:
		return CausePSI
	case 4:
		return CauseMixed
	default:
		return CauseNone
	}
}

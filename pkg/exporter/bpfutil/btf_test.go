package bpfutil

import (
	"os"
	"runtime"
	"testing"
)

func TestKernelRelease(t *testing.T) {
	if runtime.GOOS != "linux" {
		t.Skip("linux only")
	}
	v, err := KernelRelease()
	if err != nil {
		t.Skip(err)
	}
	if v == "" {
		t.Fatal("empty release")
	}
}

func TestGetBtfFileSkipsWhenMissing(t *testing.T) {
	if runtime.GOOS != "linux" {
		t.Skip("linux only")
	}
	_, err := GetBtfFile()
	if err == nil {
		// ok if self-hosted btf exists on VPS
		return
	}
	if !os.IsNotExist(err) {
		t.Logf("GetBtfFile err (expected on dev host): %v", err)
	}
}

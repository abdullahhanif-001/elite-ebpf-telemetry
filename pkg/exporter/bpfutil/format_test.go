package bpfutil

import (
	"testing"
)

func TestGetV4AddrStr(t *testing.T) {
	got := GetV4AddrStr(0x0100007f) // 127.0.0.1 little-endian style input
	if got != "127.0.0.1" {
		t.Fatalf("GetV4AddrStr=%q want 127.0.0.1", got)
	}
}

func TestGetProtoStr(t *testing.T) {
	if GetProtoStr(6) != "TCP" {
		t.Fatal("expected TCP")
	}
	if GetProtoStr(17) != "UDP" {
		t.Fatal("expected UDP")
	}
}

func TestGetHumanTimes(t *testing.T) {
	if GetHumanTimes(500) != "500 ns" {
		t.Fatal("ns")
	}
	if GetHumanTimes(5000) != "5 us" {
		t.Fatal("us")
	}
	if GetHumanTimes(5_000_000) != "5 ms" {
		t.Fatal("ms")
	}
}

func TestGetCommString(t *testing.T) {
	var comm [20]int8
	copy(comm[:], []int8{'h', 'e', 'l', 'l', 'o'})
	if GetCommString(comm) != "hello" {
		t.Fatalf("comm=%q", GetCommString(comm))
	}
}

func TestHtons(t *testing.T) {
	// htons on little-endian host should swap
	v := Htons(0x1234)
	if v == 0x1234 {
		t.Fatal("expected byte swap")
	}
}

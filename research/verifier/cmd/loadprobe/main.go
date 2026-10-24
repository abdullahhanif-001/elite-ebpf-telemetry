// loadprobe — load a compiled BPF object via cilium/ebpf (research oracle).
package main

import (
	"encoding/json"
	"fmt"
	"os"

	"github.com/cilium/ebpf"
)

type verdict struct {
	Object   string `json:"object"`
	LoadOK   bool   `json:"load_ok"`
	Error    string `json:"error,omitempty"`
	Programs int    `json:"programs"`
}

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: loadprobe <file.o>")
		os.Exit(2)
	}
	path := os.Args[1]
	spec, err := ebpf.LoadCollectionSpec(path)
	v := verdict{Object: path}
	if err != nil {
		v.Error = err.Error()
		emit(v, 1)
	}
	v.Programs = len(spec.Programs)
	coll, err := ebpf.NewCollection(spec)
	if err != nil {
		v.Error = err.Error()
		emit(v, 1)
	}
	defer coll.Close()
	v.LoadOK = true
	emit(v, 0)
}

func emit(v verdict, code int) {
	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	_ = enc.Encode(v)
	if v.LoadOK {
		fmt.Println("LOADPROBE_OK")
	} else {
		fmt.Println("LOADPROBE_FAIL")
	}
	os.Exit(code)
}

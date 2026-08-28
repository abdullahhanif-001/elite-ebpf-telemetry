package dcic

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

// Actuator applies Soft DCIC decisions to cgroup v2.
type Actuator interface {
	EnsureHierarchy(lcCpus, beCpus string) error
	SetBEQuotaPercent(pct int) error
	Reset() error
}

// CgroupActuator writes cpu.max and cpuset under a dedicated hierarchy.
type CgroupActuator struct {
	Root string // /sys/fs/cgroup/elite-dcic
}

// NewCgroupActuator returns a cgroup v2 actuator.
func NewCgroupActuator(root string) *CgroupActuator {
	if root == "" {
		root = "/sys/fs/cgroup/elite-dcic"
	}
	return &CgroupActuator{Root: root}
}

func (a *CgroupActuator) lcDir() string { return filepath.Join(a.Root, "lc") }
func (a *CgroupActuator) beDir() string { return filepath.Join(a.Root, "be") }

// EnsureHierarchy creates elite-dcic/lc and elite-dcic/be with cpusets.
func (a *CgroupActuator) EnsureHierarchy(lcCpus, beCpus string) error {
	if err := os.MkdirAll(a.lcDir(), 0o755); err != nil {
		return err
	}
	if err := os.MkdirAll(a.beDir(), 0o755); err != nil {
		return err
	}
	// Enable controllers on parent if possible (best-effort).
	_ = writeFile(filepath.Join(a.Root, "cgroup.subtree_control"), "+cpu +cpuset")
	if lcCpus != "" {
		if err := writeFile(filepath.Join(a.lcDir(), "cpuset.cpus"), lcCpus); err != nil {
			// Some hosts need cpuset.cpus.effective — ignore if unsupported.
			_ = err
		}
		_ = writeFile(filepath.Join(a.lcDir(), "cpuset.mems"), "0")
	}
	if beCpus != "" {
		_ = writeFile(filepath.Join(a.beDir(), "cpuset.cpus"), beCpus)
		_ = writeFile(filepath.Join(a.beDir(), "cpuset.mems"), "0")
	}
	return nil
}

// SetBEQuotaPercent sets cpu.max for BE as percent of one CPU (100000 period).
func (a *CgroupActuator) SetBEQuotaPercent(pct int) error {
	if pct < 1 {
		pct = 1
	}
	if pct > 100 {
		pct = 100
	}
	period := 100000
	quota := period * pct / 100
	if pct >= 100 {
		return writeFile(filepath.Join(a.beDir(), "cpu.max"), "max "+strconv.Itoa(period))
	}
	return writeFile(filepath.Join(a.beDir(), "cpu.max"), fmt.Sprintf("%d %d", quota, period))
}

// Reset restores BE to max and leaves hierarchy in place.
func (a *CgroupActuator) Reset() error {
	return a.SetBEQuotaPercent(100)
}

// MovePID places a process into lc or be.
func (a *CgroupActuator) MovePID(class string, pid int) error {
	dir := a.beDir()
	if class == "lc" {
		dir = a.lcDir()
	}
	return writeFile(filepath.Join(dir, "cgroup.procs"), strconv.Itoa(pid))
}

func writeFile(path, body string) error {
	return os.WriteFile(path, []byte(body), 0o644)
}

// ReadCPUPressure returns some avg10 from /proc/pressure/cpu or 0.
func ReadCPUPressure() float64 {
	b, err := os.ReadFile("/proc/pressure/cpu")
	if err != nil {
		return 0
	}
	// some avg10=0.00 avg60=0.00 avg300=0.00 total=...
	for _, line := range strings.Split(string(b), "\n") {
		if !strings.HasPrefix(line, "some ") {
			continue
		}
		for _, f := range strings.Fields(line) {
			if strings.HasPrefix(f, "avg10=") {
				v, _ := strconv.ParseFloat(strings.TrimPrefix(f, "avg10="), 64)
				return v
			}
		}
	}
	return 0
}

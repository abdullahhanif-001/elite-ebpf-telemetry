package dcic

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

// ResctrlActuator applies L3 CAT schemata under /sys/fs/resctrl when Track B capable.
// Soft cgroup actuator remains the Contabo default; this is used only when capability allows.
type ResctrlActuator struct {
	Root     string // /sys/fs/resctrl
	CtrlGroup string // elite_be
	Cgroup   *CgroupActuator
	defaultSchemata string
}

// NewResctrlActuator wraps Soft cgroup + optional resctrl.
func NewResctrlActuator(resctrlRoot string, cg *CgroupActuator) *ResctrlActuator {
	if resctrlRoot == "" {
		resctrlRoot = "/sys/fs/resctrl"
	}
	return &ResctrlActuator{
		Root:      resctrlRoot,
		CtrlGroup: "elite_be",
		Cgroup:    cg,
	}
}

func (a *ResctrlActuator) EnsureHierarchy(lcCpus, beCpus string) error {
	if a.Cgroup != nil {
		if err := a.Cgroup.EnsureHierarchy(lcCpus, beCpus); err != nil {
			return err
		}
	}
	if !a.Available() {
		return nil
	}
	dir := filepath.Join(a.Root, a.CtrlGroup)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return fmt.Errorf("resctrl mkdir: %w", err)
	}
	// Capture default root schemata for rollback.
	if b, err := os.ReadFile(filepath.Join(a.Root, "schemata")); err == nil {
		a.defaultSchemata = string(b)
	}
	return nil
}

// Available reports whether resctrl L3 info exists.
func (a *ResctrlActuator) Available() bool {
	_, err := os.Stat(filepath.Join(a.Root, "info", "L3"))
	return err == nil
}

// SetBEQuotaPercent maps Soft quota percent onto a reduced L3 CBM mask when possible,
// and always mirrors Soft cgroup quota.
func (a *ResctrlActuator) SetBEQuotaPercent(pct int) error {
	if a.Cgroup != nil {
		if err := a.Cgroup.SetBEQuotaPercent(pct); err != nil {
			return err
		}
	}
	if !a.Available() {
		return nil
	}
	cbm, err := a.readCBMMask()
	if err != nil {
		return nil // soft-only fallback
	}
	mask := shrinkCBM(cbm, pct)
	dir := filepath.Join(a.Root, a.CtrlGroup)
	_ = os.MkdirAll(dir, 0o755)
	body := fmt.Sprintf("L3:0=%s\n", mask)
	return os.WriteFile(filepath.Join(dir, "schemata"), []byte(body), 0o644)
}

// Reset restores Soft quota and removes elite_be resctrl group when present.
func (a *ResctrlActuator) Reset() error {
	if a.Cgroup != nil {
		_ = a.Cgroup.Reset()
	}
	if !a.Available() {
		return nil
	}
	dir := filepath.Join(a.Root, a.CtrlGroup)
	// Best-effort remove control group (may fail if tasks remain).
	_ = os.Remove(dir)
	if a.defaultSchemata != "" {
		_ = os.WriteFile(filepath.Join(a.Root, "schemata"), []byte(a.defaultSchemata), 0o644)
	}
	return nil
}

func (a *ResctrlActuator) readCBMMask() (string, error) {
	b, err := os.ReadFile(filepath.Join(a.Root, "info", "L3", "cbm_mask"))
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(b)), nil
}

// shrinkCBM keeps approximately pct% of low-order bits of the CBM mask.
func shrinkCBM(mask string, pct int) string {
	if pct >= 100 {
		return mask
	}
	if pct < 1 {
		pct = 1
	}
	v, err := strconv.ParseUint(mask, 16, 64)
	if err != nil || v == 0 {
		return mask
	}
	bits := 0
	for x := v; x > 0; x >>= 1 {
		bits++
	}
	keep := bits * pct / 100
	if keep < 1 {
		keep = 1
	}
	var out uint64
	for i := 0; i < keep; i++ {
		out |= 1 << i
	}
	return fmt.Sprintf("%x", out)
}

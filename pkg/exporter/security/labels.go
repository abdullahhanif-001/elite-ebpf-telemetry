package security

import (
	"fmt"
	"regexp"
	"strings"
)

const maxLabelValueLen = 256

var labelNameRe = regexp.MustCompile(`^[a-zA-Z_][a-zA-Z0-9_]*$`)

// SanitizeLabelValue strips control chars and caps length for Prometheus/OTLP safety.
func SanitizeLabelValue(v string) string {
	v = strings.Map(func(r rune) rune {
		if r < 0x20 || r == 0x7f {
			return -1
		}
		return r
	}, v)
	if len(v) > maxLabelValueLen {
		v = v[:maxLabelValueLen]
	}
	return v
}

// ValidateAdditionalLabelEntry ensures key=value format and valid Prometheus label name.
func ValidateAdditionalLabelEntry(entry string) (key, valueExpr string, err error) {
	parts := strings.SplitN(entry, "=", 2)
	if len(parts) != 2 {
		return "", "", fmt.Errorf("invalid additionalLabels entry %q: expected key=value", entry)
	}
	key = strings.TrimSpace(parts[0])
	valueExpr = strings.TrimSpace(parts[1])
	if !labelNameRe.MatchString(key) {
		return "", "", fmt.Errorf("invalid label name %q", key)
	}
	return key, valueExpr, nil
}

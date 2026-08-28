# Threat Model (ECGF-lite)

| Threat | Mitigation | Residual |
|--------|------------|----------|
| MOCK agent egress/exfil | Envelope deny connect/open | Kernel compromise |
| Bus tampering by unprivileged user | `0640` root-owned decision path | root attacker |
| Disable elite-ecgf | Sticky fail-closed envelope option | operator error |
| CAP_BPF load by test user | no caps | root |
| Prompt injection text | **Out of scope** — consequence only | semantic attacks |

Kernel already owned → ECGF cannot protect.

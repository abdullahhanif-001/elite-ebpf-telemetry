# Math Model (ECGF-lite)

**UNPROVEN** until Server benches.

Let posture loop period be \(T=1s\). Cost per tick: scrape/parse decision \(C_r\) + metric publish \(C_m\). Amortized CPU fraction \(\approx (C_r+C_m)/T\).

Envelope deny latency \(L_d\): kernel path (Landlock/seccomp) expected \(\ll 1ms\); userspace notify path higher.

Security coverage \(S\): fraction of red-team A1–A3 blocked. Target \(S=1.0\) for MVP.

Superiority: posture ON must not add more than \(0.05\) cores vs static envelope baseline while \(S_{\text{posture}} \ge S_{\text{static}}\).

# Date parsing performance

Run `python3 scripts/benchmark-date-parsing.py` to compile the production parser
with `swiftc -O` and measure seven batches of 5,000 mixed timestamps. The harness
uses synthetic data and never launches the app. `/usr/bin/time -l` reports CPU
time, peak RSS, and retired instructions for the executable, excluding compilation.
Pass a base revision's exported `src/Format.swift` as the optional argument for
an identical baseline workload. Alternate base/head ordering and avoid overlapping
builds or benchmarks. Compare checksums before comparing timings.

On Apple M3, macOS 26.6.2, Swift 6.3.3, a head-then-base repeat measured:

| Metric | Base | Updated |
| --- | ---: | ---: |
| Median per 5,000 parses | 824.05 ms | 162.34 ms |
| Executable user CPU, all seven batches plus warmup | 5.77 s | 1.14 s |
| Retired instructions | 91.36 billion | 18.21 billion |

This is about 80% less parser time. The checksum was identical. The earlier
base-then-head pass also improved (996.81 to 160.07 ms), but overlapped other
build work; use the repeat for comparison. Peak RSS stayed around 9 MB, so no
meaningful memory reduction is claimed. This measures the parser, not whole-app
refresh/network latency, energy, or UI frame time.

The two fixed formatter instances are protected by a lock because callers can
run concurrently. No input/output cache grows with account history. Parsing
preserves the existing fractional-first fallback. Run `swift test` for the
legacy-equivalence corpus, concurrent parsing, and the full application suite
(80 tests passed during verification).

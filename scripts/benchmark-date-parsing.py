#!/usr/bin/env python3
"""Benchmark the actual parser without launching Comux or reading account data.

Usage: python3 scripts/benchmark-date-parsing.py [path/to/Format.swift]
Run against base and head alternately, with the same Swift compiler and machine.
"""
import pathlib
import subprocess
import sys
import tempfile

source = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parents[1] / 'src/Format.swift'
parser = source.read_text().split('\nfunc formatCountdown', 1)[0].replace('import SwiftUI', 'import Foundation')
harness = r'''
let values = ["2026-09-05T12:34:56Z", "2026-09-05T12:34:56.123Z",
              "2026-09-05T20:34:56+08:00", "", "invalid"]
var checksum = 0.0
for i in 0..<100 { checksum += parseISO8601Date(values[i % values.count])?.timeIntervalSince1970 ?? 0 }
var samples: [Double] = []
for _ in 0..<7 {
    let start = DispatchTime.now().uptimeNanoseconds
    for i in 0..<5000 {
        autoreleasepool { checksum += parseISO8601Date(values[i % values.count])?.timeIntervalSince1970 ?? 0 }
    }
    samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
}
samples.sort()
print("5000 mixed parses: median_ms=\(samples[3]) min_ms=\(samples[0]) max_ms=\(samples[6]) checksum=\(checksum)")
'''
with tempfile.TemporaryDirectory(prefix='comux-date-bench-') as directory:
    main = pathlib.Path(directory) / 'main.swift'
    binary = pathlib.Path(directory) / 'benchmark'
    main.write_text(parser + harness)
    subprocess.run(['swiftc', '-O', '-swift-version', '6', str(main), '-o', str(binary)], check=True)
    subprocess.run(['/usr/bin/time', '-l', str(binary)], check=True)

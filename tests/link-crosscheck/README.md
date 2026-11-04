# Link CryptoKit cross-check

A standalone Swift program that checks the Noise vectors in `tests/fixtures/link/noise-vectors.json` against CryptoKit. Run it by hand on a Mac with the Swift toolchain. It is not part of the test script or CI, and it is not in `project.yml`. It prints one tick per vector, and the four ticks it prints are the cross-check the contract cites.

```bash
swiftc -O tests/link-crosscheck/xcheck.swift -o "${TMPDIR:-/tmp}/g2-xcheck" && "${TMPDIR:-/tmp}/g2-xcheck" tests/fixtures/link/noise-vectors.json
```

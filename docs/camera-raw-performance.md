# Camera Raw scope sampling benchmark

Measured October 14, 2026 on this Mac (Apple silicon, 10 logical processors), macOS 27.0.1. Release configuration, code coverage and parallel test execution disabled.

Only histogram/vectorscope sampling changes: every second pixel in both directions becomes every fourth through 4,000,000 pixels and every eighth above that. Image effects, their order, clipping overlays and preview resolution stay unchanged.

## Method

Deterministic opaque RGBA fixtures contain gradients and seeded color noise, at 2, 4, 6, 24 and 48 megapixels. These are synthetic images, not a representative photo corpus. Each variant uses the same source, settings and cached brightness measurement. Light uses Exposure +0.5, Contrast +15 and Highlights −20. The heavier 24 MP case additionally uses Shadows +25 and Clarity +15.

Scope timing includes both RGB histogram and vectorscope construction. Preview timing measures `CameraRawScope.preview`, including image filtering and scope generation. It excludes fixture creation, initial brightness measurement, UI event queueing, canvas composition, texture upload and display presentation. These are warmed render timings, not input-to-screen latency.

## Separate before/after runs

The baseline was measured before editing production code. The identical benchmark was then rerun after changing the sampling rule. Two warm-ups precede 15 scope trials and seven preview trials per case. Values below are medians.

| Image / settings | Scope before | Scope after | Preview before | Preview after | Preview time reduction |
| --- | ---: | ---: | ---: | ---: | ---: |
| 2 MP / Light | 2.03 ms | 0.52 ms | 11.73 ms | 10.66 ms | 9.1% |
| 4 MP / Light | 2.83 ms | 0.76 ms | 18.62 ms | 17.16 ms | 7.8% |
| 6 MP / Light | 4.83 ms | 0.36 ms | 27.87 ms | 22.86 ms | 18.0% |
| 24 MP / Light | 18.58 ms | 1.17 ms | 98.74 ms | 77.75 ms | 21.3% |
| 24 MP / Light + Shadows + Clarity | 18.58 ms | 1.17 ms | 604.24 ms | 556.01 ms | 8.0% |
| 48 MP / Light | 38.87 ms | 2.39 ms | 198.96 ms | 176.31 ms | 11.4% |

The larger apparent improvement in the heavy case exceeds the isolated scope savings. Separate-run results include system-load, cache and CPU-frequency variation; the paired check below helps distinguish that variation from the sampling benefit.

## Paired confirmation

Two warm-ups per variant, then 15 alternating scope pairs and 11 alternating preview pairs in the same process. Old/new order reverses each pair. The original reference uses the unchanged effect renderer plus the original step-2 C scope kernel; the new path uses the production preview renderer. These ordinary jobs have no clipping or masking overlays.

| Image / settings | Scope before | Scope after | Preview before | Preview after | Preview time reduction |
| --- | ---: | ---: | ---: | ---: | ---: |
| 2 MP / Light | 1.69 ms | 0.46 ms | 11.75 ms | 10.49 ms | 10.7% |
| 4 MP / Light | 2.85 ms | 0.74 ms | 18.83 ms | 16.68 ms | 11.4% |
| 6 MP / Light | 4.79 ms | 0.35 ms | 27.16 ms | 22.14 ms | 18.5% |
| 24 MP / Light | 18.71 ms | 1.35 ms | 122.24 ms | 106.79 ms | 12.6% |
| 24 MP / Light + Shadows + Clarity | 20.08 ms | 1.44 ms | 622.56 ms | 603.68 ms | 3.0% |
| 48 MP / Light | 38.38 ms | 2.69 ms | 194.55 ms | 157.18 ms | 19.2% |

The isolated scope calculation is about 93% cheaper on large fixtures. The overall benefit is useful for Light-only updates (roughly 11–19% lower median render time here), but modest with Shadows and Clarity (3%). Image effects dominate the heavy case. These measurements do not establish a GPU migration benefit or an input-to-screen frame rate.

The 24 MP Light trials varied substantially: original 108.17–153.24 ms, new 90.00–149.75 ms. The heavier trials also overlap: original 588.36–635.78 ms, new 568.72–647.19 ms. Treat the medians as workload-specific observations, not guaranteed speedups.

Functional checks cover the 4 MP threshold, histogram and vectorscope sample counts, color-bin placement, and the existing Camera Raw slider accuracy and preview tests.

## Reproduce

The opt-in benchmark is `CompositorTests/CameraRawScopePerformanceTests.swift`. Run it alone, using the same Release configuration as the measurements:

```sh
TEST_RUNNER_CAMERA_RAW_BENCHMARK=1 xcodebuild \
  -project Compositor.xcodeproj -scheme Compositor -configuration Release \
  -destination 'platform=macOS' -derivedDataPath /tmp/CompositorScopeBenchmarkBuild \
  CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES \
  -enableCodeCoverage NO -parallel-testing-enabled NO \
  -only-testing:CompositorTests/CameraRawScopePerformanceTests test
```

It writes `/tmp/compositor-scope-paired.json`. Normal test runs return immediately unless the benchmark variable is set. Scope counts and displayed color distributions can differ slightly with sparser sampling; the image pixels, clipping overlays, and effect math do not change.

## Raw results

All original trials are retained in [camera-raw-scope-sampling.json](benchmarks/camera-raw-scope-sampling.json).

- `/tmp/compositor-scope-baseline.json`: baseline sampling, measured before the edit.
- `/tmp/compositor-scope-after.json`: new sampling, measured after the edit.
- `/tmp/compositor-scope-paired.json`: alternating original/new sampling within one process.
- `/tmp/CompositorScopeBenchmarkBefore.log`, `/tmp/CompositorScopeBenchmarkAfter.log`, `/tmp/CompositorScopeBenchmarkPaired.log`: Xcode run logs.

# D3 — Finding a GPU-capable CI for Metal verification

**Question:** can we run the Metal tests (compute pipeline, IOSurface, end-to-end
GLSL→MSL→dispatch) in CI, without buying a Mac?

**Answer: no free/virtualized option exists. Metal needs bare-metal Apple hardware.**

## Why virtualized CI can't do Metal
macOS guests under Apple's **Virtualization.framework** do not get a GPU. Confirmed two ways:
- GitHub Actions `macos-14` (Apple Silicon) runners: our headless tests report
  `MTLCreateSystemDefaultDevice() == nil` ("no Metal device").
- Tart (the VM tool Cirrus CI and most Apple-Silicon Mac CI use) —
  [issue #1032](https://github.com/cirruslabs/tart/issues/1032): macOS guests show
  "null for Graphics/Display"; no GPU passthrough, no documented workaround.

So **GitHub Actions, Cirrus, and anything Virtualization.framework-based is a dead end**
for Metal. The CPU tests (transpiler, trampolines, Java) run fine there; the Metal tests
will always skip.

## What does have Metal: bare-metal Macs
| Option | Metal? | Cost | Notes |
|---|---|---|---|
| AWS EC2 `mac2.metal` (M1, 8 GPU cores) | ✅ | $0.65/hr, **24h min** ≈ $15.60/session | Apple license forces a 24-hour dedicated-host lease |
| Scaleway / MacStadium Apple Silicon | ✅ | similar, 24h min | bare-metal Mac minis |
| Used **Mac mini M1** as self-hosted runner | ✅ | ~one-time $300–500 | best long-run; headless by design |

Apple's macOS license requires a **24-hour minimum** lease on all cloud Macs, so none of
them are economical per-commit.

## Recommended verification strategy
CI stays as-is (CPU tests gate every commit; Metal tests skip). For the Metal half:

1. **Milestone verification, no purchase:** rent one AWS EC2 `mac2.metal` session
   (~$16), register it as a temporary self-hosted GitHub runner, push a branch that
   targets that runner for the `native-build` job, let the Metal/e2e tests actually run,
   then release the host. Do this at the end of a feature phase, not per commit.
2. **Ongoing:** a used Mac mini M1 as a permanent self-hosted runner — Metal tests then
   run on every push for ~$0 marginal cost. Best if the project continues seriously.

Either way, no code change is needed beyond pointing `native-build` at a self-hosted
runner: the headless tests already exit 2 (skip) without a device and 0/1 with one.

## Bottom line
The "free GPU CI" hope is dead — Virtualization.framework has no Metal. But the cost to
verify is bounded and small: ~$16 for a one-off cloud verification, or a cheap used Mac
mini for continuous coverage. Everything else (the entire transpiler + trampoline layer)
is already CPU-verified for free.

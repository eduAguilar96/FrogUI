# Diagnostics

F6 inspection exposes readable component provenance, arranged bounds, focus and
interaction state, and the deepest hits under a pointer. Definition provenance
is captured once per semantic owner and continues to work when FrogUI is nested
under a vendor path.

The optional Host diagnostics profiler records bounded rolling phase timings,
activity, net Lua heap movement, rebuild causes, semantic render owners, dirty
and quiet cohorts, and one correlated slow frame. Enable it only when measuring:

```lua
host:setDiagnosticsEnabled(true)
local snapshot = host:diagnostics()
```

Snapshots and message traces are detached diagnostic records, not runtime
state. Net negative heap movement is context, not proof of a garbage collection
event. Measure full consumer workloads before attributing a frame problem to
the framework.

Private allocation and render-replay probes support focused framework work but
are not 0.x consumer API. Do not build application behavior around them or
`Host:tree()`.

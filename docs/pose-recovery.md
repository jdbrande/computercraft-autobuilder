# Interrupted movement recovery

An updated worker with an active owned task can automatically recover interrupted
translations and turns using ComputerCraft GPS. Configure real wireless GPS hosts
in noncoplanar positions covering the work area and enable GPS on the worker:

```lua
gps={enabled=true,timeout=2,interval=30},
```

A translation interrupted by reboot keeps its movement journal. GPS must locate
the turtle at the recorded starting or ending coordinate. An unexpected fix keeps
the journal and reports that the pose needs inspection; it does not silently invent
a new route. Existing `pose x y z heading` confirmation can deliberately reconcile
an operator-observed pose before a heading probe owns movement.

GPS cannot directly measure heading. After an interrupted turn, the worker requests
exclusive controller ownership of its starting cell and all four possible horizontal
probe cells. It inspects ahead without digging, checks fuel and loading/protection,
and moves forward once. GPS measures the resulting direction. The turtle then backs
up to its starting cell and acknowledges recovery before resuming the original job.
Returning to the origin preserves mining trails and in-progress route journals.

The worker display shows recovery phase and any refusal. A blocked candidate may
need its other owner to return, an obstruction removed, assured loading restored or
GPS coverage repaired. No automatic probe occurs without enough fuel for the probe,
backtrack and existing depot return reserve. A missing GPS fix cannot authorize
another blind move. An interrupted probe/backtrack reconciles its physical outcome
from fresh GPS rather than repeating it. Claims stay owned during disconnects.

Paused jobs stay paused. Disabled worker automation performs no generic task or probe
effects. Recovery resumes only pose-related blocked work, preserving cargo, supply,
excavation and placement journals. Controller and worker both retain the original
job identity. Lost recovery grants and settlement acknowledgements are retried, including after
GPS disappears once physical return is settled. Mining-only workers can recover
without enabling generic automation. Controller fallback restores reported probe
claims before allowing conflicting movement; worker fallback restores only heading
evidence consistent with its recorded probe path. Old controller grants are fenced
after reconnect. A worker keeps its latest settlement receipt for reconciliation.

A probe requires all four possible cells to be reservable, even though it physically
uses only the forward cell. It cannot dig or turn through an obstruction. It does not
solve arbitrary route blockage or traffic deadlocks. GPS hosts and loaded terrain must
already exist. First-install idle heading calibration, reachable inventory rescue,
final home/unload settlement and broader recovery commands remain required fleet work.
An active probe must settle its origin before manual pose confirmation can override it.

See [native acceptance](validation-0.20.0.md) for actual interrupted hardware results.

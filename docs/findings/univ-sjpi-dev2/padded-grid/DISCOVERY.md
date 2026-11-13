# Bounded padded-grid discovery family

Initial baseline: 1d63b2b5bd4d44dfcb937322bc559ca85b9d371d.
This is a hypothesis, not an assumption of SAS's grid size or bin mapping.

All predictors operate on a proposed 401-point padded grid, use only x/low/high,
and return a GLOBAL padded index. They do not receive the observed target k.
The scored original-grid index is padded_index-100; no clamping to 100..300
or forcing of min/max assignments is allowed.

The bounded discovery family has 2 origins x 2 spacings x 16 decisions = 64:

- fingerprint endpoints: o=((low-R)+low)/2 and u=((high+R)+high)/2, every
  operation stored binary64, R=high-low;
- direct-half-range control: o=low-R/2 and u=high+R/2;
- spacing: R/200, or (u-o)/400, to distinguish original-range from a padded
  endpoint linspace calculation without silently assuming they are bit-equal;
- z=x-o is stored before any decision;
- q=z/d or z*(1/d), then floor(q+.5) or nearest-even integer conversion;
- alternatively find the nearest of 401 centers, with either distance tie
  choice, or compare with stored pairwise midpoints with either equality choice;
- center representations are j*d, (o+j*d)-o, or fma(j,d,o)-o. The latter two
  distinguish stored absolute centers and possible center-construction fusion.

These arithmetic differences are tied specifically to the proposed origin,
grid spacing and stored-center mechanism. No q-only tolerance family, free
precision search, measured threshold lookup, or index-specific constant is
introduced. The existing SJPI pilot/solver is not fitted or changed.

All 163 previous assignments and all 72 recorded transition queries must pass;
all six first-right thresholds must match exactly. Verify min/max padded
indices 100/300, occupancy confined to 100..300, and count conservation on the
retained sample sets. A model failing any prerequisite is not viable.

If no model passes, report concrete counterexamples and stop this discovery
family. If models pass, choose the first passing model in the fixed tuple order
in model.py (fingerprint origin and R/200 spacing first), freeze its code/hash
and identity BEFORE new heldout outcomes, and run new indices/domains AND
independent whole-sample bandwidth probes. Only then implement a raw adapter.
Metadata and degenerate/numerical-boundary behavior must remain explicit.

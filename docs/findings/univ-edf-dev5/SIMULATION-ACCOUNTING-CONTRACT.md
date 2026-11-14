# Simulation accounting — pending owner confirmation

Dev4 owns confirming the conditional-Pareto fixed-sigma/free-alpha behavior
across seeds and requested counts. Dev5 owns the additive inference API after
that evidence/contract is confirmed. No duplicate conditional-Pareto oracle
work is being run here.

Parent-reported provisional observation: requested 5000 simulations produced
p-values 1078/4925, 224/4925 and 123/4925. This is not treated as complete
validation of the failure classification or budget policy.

The existing `Simulator.draw -> diag.Error!Statistics` and `simulate` remain
a strict, backward-compatible entry point. Its error propagation is not a
blanket prohibition on SAS-validated numerical exclusions.

Requirements for the forthcoming additive proposal:

- A new typed outcome distinguishes usable statistics from an explicitly
  classified expected numerical refit failure. Do not catch arbitrary
  ParseError/ExecError and silently convert it into a failed replicate.
- Preserve malformed/unsupported-request and resource-error propagation.
- Return attempted, valid and failed counts. Use the confirmed valid-replicate
  denominator for probabilities and standard errors when exclusions apply.
- Preserve seed reproducibility and report the attempt/replacement policy;
  do not silently draw replacement replicates.
- With no valid replicates, fail loudly rather than return NaN probabilities.
- Keep the existing callback source-compatible. A separate counted-outcome
  entry point can share its validation/aggregation machinery.
- Adapter diagnostics must distinguish counted numerical failures from fatal
  errors; counted failures must not erase or masquerade as malformed requests.

Exact type/function signatures and the adapter policy will be coordinated via
the parent after dev4 confirms the evidence. This checkpoint does not implement
or claim acceptance of the new exclusion policy. It does complete the tabulated
families, including their distinct bounds and unavailable-statistic rules.

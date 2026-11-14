# Dev5 retained checkpoint state

Worktree: /Users/thomas/kirha/opensas-dev5. Branch: dev5. Scope remains the EDF
inference helper and uniquely named evidence/tests. No shared fitting, parser,
distribution, PROC, ODS or dev4 GOF file edits; no Jira, fetch, pull or push.
The parent ticket is not closed by this support checkpoint.

All assigned tabulated EDF families/masks are now implemented and independently
verified against M9. README.md and EVIDENCE-*.md are the current acceptance
inventory. Earlier mathematical exploration is preserved in the unique scratch
folder /tmp/opensas-dev5-edf-round2-20261113; no interrupted work was reset.
The successful replay scripts contain the accepted extraction algorithms.

Integration still owned by dev4: filter exponential threshold-boundary values
only after fitting, pass original n plus exponential_boundary_count, preserve
unrounded shapes and the exact lognormal sigma=1 upper-regime choice, and use
nullable results for EDF row publication. See the boundary evidence document.

Simulation accounting remains open: dev4 validates expected numerical-failure
exclusions; dev5 adds a typed/counting API after confirmation. Existing strict
callbacks still propagate errors. See SIMULATION-ACCOUNTING-CONTRACT.md.

Latest parent notification before landing preparation: f36b582. The final chat
report records actual rebased base/HEAD and full gate counts. Do not infer a
green SHA from an earlier unit run or from this file. Preserve the one final
rebase / full-gate / green-marker landing protocol and stay available for bounce.

/* BUG-procwhereoptswallow: a PROC data=NAME(where=(…)) dataset OPTION whose
   predicate names an UNKNOWN variable had its ERROR swallowed by the local
   option-diags sink — the proc silently printed an EMPTY table and exited 0
   (a malformed predicate silently printed the FULL table). SAS 9.4:
   "ERROR: Variable nosuchvar is not on file d" and no output. The first two
   procs prove the valid paths still work: a good where= filters to v>10, and
   a benign keep=/drop= keeps all rows without a spurious error (the DKRICOND
   warning drop is intentional). The last proc's unknown variable must fail
   LOUD and abort the step, printing NOTHING (captured diagnostics, exit 1) —
   it runs LAST because a step ERROR puts the run in syntax-check mode
   (BUG-errhalt). If the swallow regresses, the 3rd proc prints an empty
   table here and mismatches.
   expect-rc: 1 */
data d; input id v; datalines;
1 10
2 20
3 30
;
run;
proc print data=d(where=(v>10)) noobs;
  var id v;
run;
proc print data=d(keep=id drop=v) noobs;
run;
proc print data=d(where=(nosuchvar>1)) noobs;
  var id v;
run;

/* GH#3 ISS-steperrhalt: `options nosyntaxcheck;` opts OUT of the post-step-error
   stop-all for the REST of the run (Language Reference: Concepts pp.170/177-178:
   error processing is mode-dependent — the stop-all is BATCH's default and stays
   opensas's default; the option is the documented control, not a default flip.
   docs/decisions.md D-024).

   The failing step (SET of a dataset that does not exist) still halts ITSELF and
   still fails the run: the recorded ERROR keeps the exit code at 1 (expect-rc: 1
   — the option changes WHICH steps run, never the exit code, D-002 fail-loud).

   Everything below the failing step is INDEPENDENT of it, so under
   NOSYNTAXCHECK it all executes: both PUT steps and the PROC PRINT table land
   on stdout, which is what this golden pins. Under the DEFAULT (no option) the
   same program would print nothing after `data src` — the skip gate eats every
   later step (BUG-errhalt). The exec-layer per-step gates stay honest because
   main spends the stale step-error class before each later step (diag.zig
   spendStepErrors): `data ok1` really reads SRC and really PUTs both rows. */
data src;
  input x;
  datalines;
1
2
;
run;

options nosyntaxcheck;

data gone;
  set no_such_ds;
run;

data ok1;
  set src;
  put 'independent-one ran, x=' x;
run;

proc print data=src;
run;

data ok2;
  set src;
  put 'independent-two ran';
run;

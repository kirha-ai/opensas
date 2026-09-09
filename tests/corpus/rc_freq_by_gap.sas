/* GAP-gapsexitingone §5b (a129c58f) — the end-to-end half of proc.zig's
   in-source D-009 pins: a recognized-but-unsupported PROC construct is an
   opensas gap, so the PROCESS exits 2 ("file an opensas issue"), not 1.
   PROC FREQ's BY statement is valid SAS 9.4; per-group tables are simply
   not modeled, and the guard names that exact construct (a typo can't
   reach it). The in-file test pins exitCode(gapHit, hasErrors)==2; this
   pins the real process rc through main.zig's exit path, so the two
   surfaces cannot drift. rc_format_badvalueopt.sas holds the rc-1 twin.
   expect-rc: 2 */
data a;
  input x;
  datalines;
1
;
run;
proc freq data=a;
  by x;
  tables x;
run;

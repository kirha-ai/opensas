/* QA tick322 — the OBSERVATION-COUNT consequences of the BUG-setstmtorder
   driver split (98c9fb3a), which set_stmt_order.sas does not pin: it checks
   values via PUT, not how many rows come out. The original bug was a silently
   DROPPED observation, so the row count is the thing most worth nailing down.

   1. `output; set a;` — the prefix runs on the EOF pass too (each iteration
      starts at the top of the step and the step stops when the SET reads past
      the end, Language Reference: Concepts p.495 steps 5-7), so a 2-obs input yields THREE rows: the
      iteration-1 row with k still missing, then the two read values. The
      explicit OUTPUT suppresses the implicit one (Language Reference: Concepts p.501).
   2. `n + 1;` before the SET — the sum var is retained, so the two output rows
      carry 1 and 2; the EOF pass bumps it to 3 but writes nothing.
   3. STOP in the prefix ends the step with NO read and no output for that
      iteration — 4-obs input, stop at _N_=3, so 2 rows.
   4. A LINK whose label block sits entirely AFTER the driving SET's own
      statement must keep working: LINK returns control to the statement after
      the LINK (Language Reference: Concepts p.485 Table 20.3), so it never crosses the read. */
data a2; input k @@; datalines;
1 2
;
run;
data a4; input k @@; datalines;
1 2 3 4
;
run;
data o1;
  output;
  set a2;
run;
proc print data=o1; run;
data o2;
  n + 1;
  set a2;
run;
proc print data=o2; run;
data o3;
  if _n_ = 3 then stop;
  set a4;
run;
proc print data=o3; run;
/* y is dropped on purpose: whether a plain assignment BEFORE the SET claims the
   earlier PDV slot is a separate open question (QA tick322 F7), so this fixture
   pins the LINK, not the column order. */
data o4(drop=y);
  y = 1;
  set a2;
  link addup;
  return;
addup:
  x = k + 100;
  return;
run;
proc print data=o4; run;

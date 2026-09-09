/* QA tick364 cross-landing: POINT= beside a driver, for the drivers
   merge_point_lookup does NOT cover. BUG-pointmergelookup hoisted the POINT=
   guards and the point-source resolution to the TOP of buildDriver, so they
   now run for EVERY driver, not just SET — this pins the three shapes that
   changed hands there and were left unpinned.

   SAS 9.4 Statements ref, SET POINT= (printed p.336): "POINT= causes the SET
   statement to use random (direct) access to read a SAS data set", and the
   step is driven by whatever else drives it. The loud arms — POINT= with a BY
   statement / with a WHERE statement / a POINT= source that does not exist —
   are captured-diagnostics territory, never here.

   1. MODIFY-driven + POINT= lookup: the lookup value must LAND (before
      BUG-pointmergelookup the read was parsed and silently skipped, so v kept
      its old value and the arithmetic went missing).
   2. POINT=-DRIVEN DO loop with NOBS=: the p.336 "Requirement: a STOP
      statement" idiom, one row per explicit OUTPUT, unaffected by the
      point_driven re-key.
   3. A CONDITIONAL POINT= read auto-retains its value across iterations
      (Language Reference: Concepts p.495 step 5 — SET-read vars retain), so the un-read iterations
      keep the last value read, not a fresh missing. */

data m; input k v; datalines;
1 10
2 20
3 30
;
run;
data lk; input q; datalines;
7
8
9
;
run;

/* 1. MODIFY drives; `set lk point=p` is a pure lookup beside it. Only k/v are
      printed: whether the lookup var itself lands in the MODIFY master is a
      separate question this fixture deliberately does not pin. */
data mm; set m; run;
data mm;
  modify mm;
  p = 2;
  set lk point=p;
  v = v + q;
run;
proc print data=mm noobs; var k v; run;

/* 2. POINT= itself drives: DO + NOBS= + STOP, explicit OUTPUT only. */
data w2;
  do p = 1 to n;
    set m point=p nobs=n;
    output;
  end;
  stop;
run;
proc print data=w2 noobs; run;

/* 3. The read happens on iteration 2 only; iteration 3 keeps that value. */
data w3;
  do i = 1 to 3;
    if i = 2 then do;
      p = 1;
      set lk point=p;
    end;
    output;
  end;
  stop;
run;
proc print data=w3 noobs; run;

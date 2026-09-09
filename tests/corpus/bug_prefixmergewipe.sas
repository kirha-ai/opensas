/* BUG-prefixmergewipe (QA tick322 F3, SILENT wrong values): columns read with
   MERGE/UPDATE/MODIFY are NOT reset to missing at the top of a DATA-step
   iteration — Language Reference: Concepts p.495 step 5 names all three explicitly ("variables that
   you read with a SET, MERGE, MODIFY, or UPDATE statement are not reset to
   missing here"). The driver split made the pre-read prefix user-visible, so
   `pre = v;` before the driver wrote a missing into the output on every row.
   SAS: the prefix sees the PREVIOUS iteration's value (missing on iteration
   1). A source absent from the current BY group still reads missing AFTER the
   read (the wipe moved to the read itself) — w is . on id 2, v is . on id 3.
   o1 MERGE: pre = ., 10, 20.  o2 UPDATE: pre = ., 10, 99 (the applied
   transaction value is what iteration 3 inherits).  o3 MODIFY (two
   transactions): pre = ., 10 on the rebuilt master.
   COLUMN ORDER (GAP-varorder-assignset): `pre` is defined by a statement that
   TEXTUALLY precedes the MERGE/UPDATE/MODIFY, so it owns slot 1 — Language Reference: Concepts printed
   p.47, "position in observation is determined by the order in which the
   variables are defined in the DATA step". `v` does NOT move with it: opensas
   declares statement TARGETS only, so the RHS mention in `pre = v;` takes no
   slot and v stays at the read (SAS would order it second). That is the
   declareVars ponytail, one rule for the whole step — this fixture is where it
   is visible, so change it here if it is ever closed. */
data m; input id v; datalines;
1 10
2 20
;
run;
data t; input id w; datalines;
1 100
3 300
;
run;
data o1;
  pre = v;
  merge m t;
  by id;
  post = v;
run;
proc print data=o1; run;
data t2; input id v; datalines;
2 99
3 30
;
run;
data o2;
  pre = v;
  update m t2;
  by id;
  post = v;
run;
proc print data=o2; run;
data m3; set m; run;
data t3; input id w; datalines;
1 100
2 200
;
run;
/* GAP-ch23med-tick296 F3: the o3 MODIFY output can no longer SHOW `pre` or `w`
   — MODIFY "cannot modify the descriptor portion of a SAS data set, such as
   adding a variable" (Statements ref printed p.240), and the transaction
   variable `w` is the reference's own NWSTOCK case (printed p.253: "MODIFY does
   not add NWSTOCK … Thus, it is not necessary to put NWSTOCK in a DROP
   statement"). The printed columns below are m3's frozen descriptor, id and v.
   THE SUBJECT IS STILL PINNED, just in the log rather than the descriptor: the
   PUT reports `pre` per iteration, so the prefix still reads missing on the
   first and the PREVIOUS iteration's value afterwards, which is what this
   fixture exists to prove. (Declaring `pre` on the master instead would NOT
   preserve it — `pre` would then be re-read from the master every iteration and
   read missing throughout, silently converting the test into a different one.)
   o1 MERGE and o2 UPDATE are untouched and pin the same rule on their paths. */
data m3;
  pre = v;
  put 'o3 ITER pre=' pre ' v=' v ' w=' w;
  modify m3 t3;
  by id;
run;
proc print data=m3; run;

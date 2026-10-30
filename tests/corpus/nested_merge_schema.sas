/* BUG-nestedsourceschema (QA tick290 F4): a nested MERGE/UPDATE/MODIFY
   contributes its columns to the compile-time PDV exactly like a nested SET.
   BUG-nestedsetdriver made every nested source declarative-only, but only
   SET got the compensating schema seed — a nested MERGE/UPDATE/MODIFY
   vanished entirely: `if 0 then merge b; stop;` emitted a dataset with ZERO
   variables. The runtime question is now pinned separately by BUG-mergebesideset:
   executing a nested MERGE/UPDATE fails loud until opensas has node-local
   MERGE/UPDATE readers. This fixture keeps the dead-branch schema idiom, plus
   the lost fail-loud ("The BY statement is required for the UPDATE statement"
   on a nested UPDATE without BY) pinned by the captured-diagnostics test in
   src/exec.zig. */
data b; input k v; datalines;
1 10
;
run;

/* control: the nested SET schema idiom (was already correct) */
data w1; if 0 then set b; stop; run;
proc contents data=w1 varnum; run;

/* nested MERGE — was 0 variables */
data w2; if 0 then merge b; stop; run;
proc contents data=w2 varnum; run;

/* nested UPDATE — was 0 variables (and without BY it silently passed) */
data w3; if 0 then update b b; by k; stop; run;
proc contents data=w3 varnum; run;

/* nested MODIFY — was 0 variables */
data w4; if 0 then modify b; stop; run;
proc contents data=w4 varnum; run;

/* nested MERGE in an ELSE branch seeds too without executing: columns k v2 w */
data a; input k v2; datalines;
1 10
;
run;
data c; input k w; datalines;
1 100
;
run;
data o; if 1 then stop; else merge a c; run;
proc contents data=o varnum; run;

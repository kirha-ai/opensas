/* BUG-doblocksourceinert (QA tick307 F1b): a nested MERGE inside a
   `do … end` block contributed NO PDV columns at all — "1 obs with
   0 variables" at exit 0, the exact fabricated-output signature
   BUG-nestedsourceschema was filed to kill, restored only for the bare-IF
   form. The .do_ arm gives the block form the same compile-time schema seed.
   The RUN-TIME semantics of a conditional MERGE/UPDATE stay needs-oracle —
   pinned for the else-branch form in nested_merge_schema as one all-missing
   obs — so this pins the identical compromise for the block form: columns
   present, never a 0-variable dataset. */
data a; input k av; datalines;
1 10
;
run;
data b; input k bv; datalines;
1 20
;
run;

/* nested MERGE in a block: schema k av bv seeded (was: 0 variables) */
data o1; if 1 then do; merge a b; by k; end; run;
proc print data=o1 noobs; run;

/* nested UPDATE in a block: same schema seed */
data o2; if 1 then do; update a b; by k; end; run;
proc print data=o2 noobs; run;

/* dead-branch block still seeds the schema, like the `if 0 then set` idiom */
data o3; if 0 then do; merge a b; by k; end; stop; run;
proc contents data=o3 varnum; run;

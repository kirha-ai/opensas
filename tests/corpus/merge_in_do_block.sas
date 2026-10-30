/* BUG-doblocksourceinert + BUG-mergebesideset: a nested MERGE inside a
   `do ... end` block still contributes compile-time PDV columns, but if the
   block executes opensas must fail loud rather than silently leave MERGE vars
   missing. Conditional MERGE/UPDATE needs a node-local reader; until that lands
   this is an opensas gap, not rc-0 fabricated data.
   expect-rc: 2 */
data a; input k av; datalines;
1 10
;
run;
data b; input k bv; datalines;
1 20
;
run;

/* nested MERGE in a block: execution is unsupported, so fail before PROC PRINT */
data o1; if 1 then do; merge a b; by k; end; run;
proc print data=o1 noobs; run;

/* nested UPDATE in a block: same schema seed */
data o2; if 1 then do; update a b; by k; end; run;
proc print data=o2 noobs; run;

/* dead-branch block still seeds the schema, like the `if 0 then set` idiom */
data o3; if 0 then do; merge a b; by k; end; stop; run;
proc contents data=o3 varnum; run;

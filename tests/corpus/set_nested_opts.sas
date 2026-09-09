/* BUG-nestedsetopts (QA tick290 F1+F2): a nested (IF-branch) SET that is the
   step's ONLY source lost its end=/point= sentinels — extractSetOptions only
   stripped the driver fields, and BUG-nestedsetdriver deliberately keeps a
   nested source out of them. Two measured failures:
   F1 (HIGH): `do until(e); if 1 then set a end=e; end;` HUNG FOREVER on a
       2-row input — set_end_var was never assigned, so e never became true.
   F2 (HIGH): `if 1 then set d end=e;` errored "File  end=e does not exist"
       with the raw \x00 sentinel in the message, and `…; set d point=i;`
       inside an iterative DO errored "a SET inside an iterative DO loop
       (without POINT=)" — factually false, POINT= was right there.
   Both are errhalt-amplified run-killers (D-014). The fix walks the whole
   step in extractSetOptions: every non-driver SET node gets the same strip,
   a nested-only source that must DRIVE (DO UNTIL/WHILE, or POINT=) is
   promoted to set_names, and a node-driven read buys the single-pass .once
   driver another iteration so `if 1 then set d end=e;` reads to EOF while
   `if 0 then set b;` still runs exactly once. */

data a; input k v; datalines;
1 10
2 20
;
run;

/* F1: nested source inside a top-level DO UNTIL — the DOW read fires at the
   node, e flags the last obs, the step TERMINATES (1 obs: k=2 v=20). */
data o1; do until(e); if 1 then set a end=e; end; run;
proc print data=o1; run;

/* F2a: nested-only END= — reads to EOF: 2 obs, e=0 then 1. */
data o2; if 1 then set a end=e; f=e; run;
proc print data=o2; run;

/* F2b: nested-only POINT= inside an iterative DO — POINT= is honored. */
data b; input v; datalines;
10
20
30
;
run;
data o3;
  do i=1 to 3;
    if i>0 then set b point=i;
    output;
  end;
  stop;
run;
proc print data=o3; run;

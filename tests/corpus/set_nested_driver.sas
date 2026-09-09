/* BUG-nestedsetdriver: a conditional SET placed BEFORE the driving SET must not
   hijack the step driver. A nested (IF-branch) source registers declarative
   effects only — the first TOP-LEVEL SET always drives.
   (1) `if _n_=1 then set params; set main;` — classic one-row lookup, reversed
       order: 3 obs, p=99 read once and RETAINED onto every obs (SAS 9.4).
       HEAD-before-fix silently produced 1 obs (params, 1 row, drove the loop).
   (2) the same lookup in driving-SET-first order — must stay identical.
   (3) `if 0 then set b; z=1; stop;` — the schema-only idiom: b's columns reach
       the PDV at compile time, 0 obs output.
   (4) `if 0 then set b; z=1; run;` without STOP: 1 obs, b's values MISSING —
       never fabricated from a SET that never executed. */
data params; input p; datalines;
99
;
data main; input m; datalines;
1
2
3
;
run;

/* (1) reversed lookup — the regression */
data o1; if _n_=1 then set params; set main; run;
proc print data=o1; run;

/* (2) driving-SET-first — same result */
data o2; set main; if _n_=1 then set params; run;
proc print data=o2; run;

/* (3) schema-only idiom: columns, no observations */
data b; input bv; datalines;
10
20
30
;
run;
data c1; if 0 then set b; z=1; stop; run;
proc contents data=c1 varnum; run;

/* (4) no STOP: one obs, no fabricated b values */
data c2; if 0 then set b; z=1; run;
proc print data=c2; run;

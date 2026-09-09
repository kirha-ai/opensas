/* BUG-pointsuppressesalloutput + BUG-pointmergelookup — ONE landing; the two
   bugs mask each other (fixing the first alone would have turned a zero-row
   failure into a quiet wrong-value one). A DATA step DRIVEN by MERGE or INPUT
   that merely MENTIONS POINT= keeps its automatic output (Language Reference: Concepts p.477 step 5;
   the p.488 no-implicit-OUTPUT rule scopes to "a SET statement that uses the
   POINT= option" DRIVING the step — 1736df6d keyed it on the MENTION and wrote
   ZERO observations at exit 0), and the POINT= read beside the driver must
   actually happen (SAS 9.4 Statements ref, SET Example 6: `set revenue; … set
   expense point=_n_;`) — before, it was parsed and then silently ignored,
   leaving the lookup columns missing. Contrast step b: genuinely POINT=-DRIVEN
   with no explicit OUTPUT → still ZERO rows (BUG-pointautooutput, unchanged).
   POINT= with a BY or WHERE statement is invalid SAS (Statements ref, SET
   POINT= Restrictions) — that fail-loud is pinned by the captured-diagnostics
   tests in src/exec.zig. */
data d; input v k $; datalines;
10 a
20 b
30 c
40 d
;
run;
data e; input z; datalines;
100
200
300
400
;
run;

/* MERGE-driven: 4 rows via the automatic output, lv/lk POPULATED from obs 2 */
data w;
  merge d e;
  p = 2;
  set d(rename=(v=lv k=lk)) point=p;
run;
proc print data=w noobs; run;

/* INPUT-driven: one observation per datalines record, direct read of obs p */
data i;
  input p;
  set d point=p;
  datalines;
1
3
;
run;
proc print data=i noobs; run;

/* POINT=-DRIVEN with no explicit OUTPUT: ZERO rows (BUG-pointautooutput stays) */
data b; p=3; set d point=p; run;
proc print data=b noobs; run;

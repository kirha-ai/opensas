/* PROC COMPARE WITH (BUG-comparewith): the WITH statement pairs positionally
   with VAR — base.VAR[k] vs compare.WITH[k] — so differently-named columns
   (prod.height vs qc.ht) are actually compared. Differing values must be
   reported; before the fix WITH was dropped and this printed a false
   "all values compared are exactly equal" (silent wrong on a QC tool). */
data prod;
  input id height weight;
  datalines;
1 165 60
2 170 75
3 158 55
;
run;
data qc;
  input id ht wt;
  datalines;
1 165 60
2 171 75
3 158 55
;
run;
/* renamed columns, ht differs in obs 2 → COMPARE must report the difference */
proc compare base=prod compare=qc;
  var height weight;
  with ht wt;
run;
/* identical renamed values → still reports all equal */
proc compare base=prod compare=qc;
  var weight;
  with wt;
run;

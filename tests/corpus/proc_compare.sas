/* PROC COMPARE: clinical double-programming QC — production vs validation. When
   the two datasets match, COMPARE reports all values exactly equal. */
data prod;
  input id x y;
  datalines;
1 10 100
2 20 200
3 30 300
;
run;
data qc;
  input id x y;
  datalines;
1 10 100
2 20 200
3 30 300
;
run;
proc compare base=prod compare=qc;
run;

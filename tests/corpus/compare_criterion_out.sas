/* BUG-comparecriterion + BUG-compareout: CRITERION=/METHOD= fuzz the numeric
   equality judgement (SAS is not bit-exact); OUT=/OUTDIF materialize the
   comparison as a dataset for downstream QC steps. */
data b;
  input id x;
  datalines;
1 1.0000001
2 2.5
;
run;
data c;
  input id x;
  datalines;
1 1.0000002
2 2.500000000001
;
run;
/* |1.0000001-1.0000002|=1e-7 <= 0.01 (absolute) and 1e-12 <= 0.01 → EQUAL. */
proc compare base=b compare=c criterion=0.01 method=absolute;
  id id;
run;
/* No CRITERION=: default fuzz (relative 1e-8) absorbs the 1e-12 diff on obs 2
   but flags the 1e-7 diff on obs 1. OUTDIF writes the base-compare DIF rows. */
proc compare base=b compare=c out=d outdif;
  id id;
run;
proc print data=d;
run;

/* Decode numeric severity to text (PROC FORMAT VALUE + put) */
proc format;
  value sevf 1="MILD" 2="MODERATE" 3="SEVERE";
run;
data ae;
  input USUBJID $ AESEVN;
  datalines;
01-001 1
01-002 3
01-003 2
;
run;
data aedec;
  set ae;
  length AESEV $10;
  AESEV = put(AESEVN, sevf.);
run;
proc print data=aedec; run;

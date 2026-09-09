/* Expand a total dose into one record per administration (multi-OUTPUT) */
data ex;
  input USUBJID $ NDOSE DOSE;
  datalines;
01-001 3 50
01-002 2 100
;
run;
data expanded;
  set ex;
  do seq = 1 to NDOSE;
    output;
  end;
  keep USUBJID seq DOSE;
run;
proc print data=expanded; run;

/* Weighted one-way frequency of responders (PROC FREQ WEIGHT) */
data counts;
  input RESP $ n;
  datalines;
Y 17
N 23
;
run;
proc freq data=counts;
  tables RESP;
  weight n;
run;

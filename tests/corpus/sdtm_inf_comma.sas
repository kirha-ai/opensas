/* COMMA informat strips grouping separators (lab counts, cell values) */
data lb;
  input LBORRES comma10.;
  datalines;
1,234
12,500
9,999,999
;
run;
proc print data=lb; run;

/* Capture min and max to two macro vars in one SELECT INTO */
data lb; input AVAL; datalines;
30
45
55
;
run;
proc sql noprint;
  select min(AVAL), max(AVAL) into :lo, :hi from lb;
quit;
data range;
  length s $20;
  s = "&lo to &hi";
run;
proc print data=range; var s; run;

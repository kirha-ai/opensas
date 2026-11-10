/* GAP-univ-summary-complete: PCTLPTS and PCTLPRE now produce requested percentile columns. */
data d;
  do g = 1 to 2;
    x = g;
    output;
  end;
run;
proc univariate data=d;
  var x;
  output out=o pctlpts=33 66 pctlpre=P median=med;
run;
proc print data=o noobs;
run;

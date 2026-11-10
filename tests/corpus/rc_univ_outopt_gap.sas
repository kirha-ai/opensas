/* GAP-univ-summary-complete: PCTLPTS without the required PCTLPRE is invalid SAS; expect-rc: 1 */
data h;
  input x;
  datalines;
1
;
run;
proc univariate data=h;
  var x;
  output out=o pctlpts=33;
run;

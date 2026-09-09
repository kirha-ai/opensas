/* GAP-gapsexitingone §5b re-verdict — INSET is a valid SAS 9.4 PROC
   UNIVARIATE statement (Syntax block, Statistical Procedures printed
   p. 298) opensas does not implement — an opensas gap, exit 2. Typo twin:
   rc_univ_stmt_typo.sas. expect-rc: 2 */
data h;
  input x;
  datalines;
1
;
run;
proc univariate data=h;
  inset x;
  var x;
run;

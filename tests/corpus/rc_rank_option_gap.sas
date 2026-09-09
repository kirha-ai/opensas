/* GAP-gapsexitingone §5b re-verdict — PRESERVERAWBYVALUES is a documented
   SAS 9.4 PROC RANK option (Procedures Guide, 7th ed., printed p. 2047)
   opensas does not implement — an opensas gap, exit 2. Typo twin:
   rc_rank_option_typo.sas. expect-rc: 2 */
data h;
  input x;
  datalines;
1
;
run;
proc rank data=h out=r preserverawbyvalues;
  var x;
run;

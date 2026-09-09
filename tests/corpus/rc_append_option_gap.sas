/* GAP-gapsexitingone §5b re-verdict — NOWARN is a documented SAS 9.4 PROC
   APPEND option (syntax diagram, Procedures Guide 7th ed. printed p. 110)
   opensas does not implement — an opensas gap, exit 2. Typo twin:
   rc_append_option_typo.sas. expect-rc: 2 */
data h;
  input x;
  datalines;
1
;
run;
proc append base=h data=h nowarn;
run;

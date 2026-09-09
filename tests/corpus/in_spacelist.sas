/* IN accepts a SPACE-separated value list, not just comma (BUG-inspacelist) */
data vs;
  input USUBJID $ VSTEST $12.;
  keepfl = (VSTEST in ("Weight" "Height" "Temperature"));
  dropfl = (VSTEST not in ("Weight" "Height"));
  datalines;
01-001 Weight
01-002 Pulse
01-003 Height
;
run;
proc print data=vs; var USUBJID VSTEST keepfl dropfl; run;

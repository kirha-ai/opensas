/* Carry the last measured position forward when marked SAME (RETAIN char) */
data vs;
  input USUBJID $ VISITNUM POSraw $;
  datalines;
01-001 1 SUPINE
01-001 2 SAME
01-001 3 STANDING
01-002 1 SITTING
01-002 2 SAME
;
run;
data carry;
  set vs;
  by USUBJID;
  length lastpos $10;
  retain lastpos;
  if first.USUBJID then lastpos = "";
  if POSraw ne "SAME" then lastpos = POSraw;
  keep USUBJID VISITNUM lastpos;
run;
proc print data=carry; run;

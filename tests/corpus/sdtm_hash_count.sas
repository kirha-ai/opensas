/* Running per-subject AE number via a hash counter (find/replace) */
data ae;
  input USUBJID $ AETERM $;
  datalines;
01-001 A
01-001 B
01-002 C
01-001 D
;
run;
data running;
  if _n_ = 1 then do;
    declare hash h();
    h.definekey("USUBJID");
    h.definedata("cnt");
    h.definedone();
  end;
  set ae;
  rc = h.find();
  if rc ne 0 then cnt = 0;
  cnt = cnt + 1;
  h.replace(key: USUBJID, data: cnt);
  output;
  keep USUBJID AETERM cnt;
run;
proc print data=running; run;

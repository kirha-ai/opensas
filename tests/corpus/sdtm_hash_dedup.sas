/* Unique subjects via a hash (add returns nonzero on a duplicate key) */
data ae;
  input USUBJID $ AETERM $;
  datalines;
01-001 A
01-001 B
01-002 C
01-003 D
01-003 E
;
run;
data uniq;
  if _n_ = 1 then do;
    declare hash seen();
    seen.definekey("USUBJID");
    seen.definedone();
  end;
  set ae;
  rc = seen.add();
  if rc = 0 then output;
  keep USUBJID;
run;
proc print data=uniq; run;

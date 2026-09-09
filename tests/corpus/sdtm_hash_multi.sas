/* Look up multiple demographics fields via a hash (multi-field definedata) */
data dm;
  input USUBJID $ SEX $ AGE;
  datalines;
01-001 M 45
01-002 F 52
01-003 M 38
;
run;
data lb;
  input USUBJID $ ALT;
  datalines;
01-001 30
01-002 45
01-003 55
;
run;
data joined;
  length SEX $1;
  if _n_ = 1 then do;
    declare hash h(dataset: "dm");
    h.definekey("USUBJID");
    h.definedata("SEX", "AGE");
    h.definedone();
  end;
  set lb;
  rc = h.find();
  keep USUBJID SEX AGE ALT;
run;
proc print data=joined; run;

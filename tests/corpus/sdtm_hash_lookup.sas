/* Look up demographics into labs via a hash table (declare hash dataset:) */
data dm;
  input USUBJID $ SEX $;
  datalines;
01-001 M
01-002 F
;
run;
data lb;
  input USUBJID $ LBSTRESN;
  datalines;
01-001 30
01-002 45
;
run;
data joined;
  if _n_ = 1 then do;
    declare hash h(dataset: "dm");
    h.definekey("USUBJID");
    h.definedata("SEX");
    h.definedone();
  end;
  set lb;
  length SEX $1;
  rc = h.find();
  keep USUBJID SEX LBSTRESN;
run;
proc print data=joined; run;

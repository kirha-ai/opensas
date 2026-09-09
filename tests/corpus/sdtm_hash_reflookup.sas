/* Decode treatment code to label via a preloaded hash (lookup join) */
data ref;
  input TRTCD TRTLBL $12.;
  datalines;
1 ACTIVE
2 PLACEBO
;
run;
data ex;
  input USUBJID $ TRTCD;
  datalines;
01-001 1
01-002 2
01-003 1
;
run;
data labeled;
  length TRTLBL $12;
  if _n_ = 1 then do;
    declare hash h(dataset: "ref");
    h.definekey("TRTCD");
    h.definedata("TRTLBL");
    h.definedone();
  end;
  set ex;
  rc = h.find();
  keep USUBJID TRTCD TRTLBL;
run;
proc print data=labeled; run;

/* GAP-opendisk: OPEN() on a disk-only member (never SET, never a literal
   lib.ds token — macro text only, a real macro's dataset-existence-check shape) must
   lazy-load it and hand back a working dsid, not 0. The load stays out of
   the Library (writeLibOutputs semantics untouched). */
libname l "tests/programs/sas7bdat_read/inputs";

%let d = %sysfunc(open(l.TE));            /* case-fallback: file is te.sas7bdat */
%let n = %sysfunc(attrn(&d, NOBS));
%let v = %sysfunc(varnum(&d, DOMAIN));
%let rc = %sysfunc(close(&d));
%let bad = %sysfunc(open(l.nope));

data _null_;
  ok = (&d > 0);
  put ok=;
  put "n=&n v=&v bad=&bad";
run;

/* BUG-informatnotfoundcontinues (Language Reference: Concepts p.518 "How SAS Handles Invalid Data"):
   an unknown/typo'd INFORMAT in INPUT reported the ERROR and then RAN THE STEP
   ANYWAY — a substituted standard read landed wrong DATA in a populated data
   set (`input x nosuchfmt5.;` printed x=12345; a plausible `mmdyy10.` typo
   wrote a populated data set of missings). An input value "requires an
   informat that is not specified" is invalid data; the mandated response does
   not include reading the field some other way. The step now STOPS before any
   value is read (the WRITE side keeps loud-then-fallback — there it only
   mis-renders). stdout pins: the step before runs, nothing after the bad
   step prints. rc=1; the ERROR text is on stderr.
   expect-rc: 1 */
data _null_;
  put "BEFORE: runs";
run;

data d;
  input x nosuchfmt5.;
datalines;
12345
;

proc print data=d; run;

data _null_;
  put "AFTER: must not print";
run;

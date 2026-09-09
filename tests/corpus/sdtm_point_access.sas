/* Read specific observations directly with POINT=. The point=/nobs= vars are
   temporary — SAS drops them from the output schema (BUG-setpointtemp); an
   explicit KEEP retains them (same override as keep-ing an end=/nobs= var). */
data src;
  input USUBJID $ AVAL;
  datalines;
01-001 100
01-002 200
01-003 300
01-004 400
;
run;
data picked;
  do i = 1, 4;
    set src point=i nobs=n;
    output;
  end;
  stop;
  keep i USUBJID AVAL;
run;
proc print data=picked; var i USUBJID AVAL; run;

/* %do bounds come from macro vars, not literals (driver-macro pattern). corpus-macroedge. */
%let lo = 3;
%let hi = 5;
%macro span;
  %do k = &lo %to &hi;
    data _null_; put "k=&k"; run;
  %end;
%mend;
%span

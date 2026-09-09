/* Loop over a fixed parameter list, deriving a flag per parameter */
%macro flagparams;
  data lb;
    set labs;
    %do i = 1 %to 3;
      %let p = %scan(ALT AST BILI, &i);
      if PARAMCD = "&p" then inpanel = 1;
    %end;
  run;
%mend;
data labs; input USUBJID $ PARAMCD $; datalines;
01-001 ALT
01-001 GGT
01-002 BILI
;
run;
%flagparams
proc print data=lb; var USUBJID PARAMCD inpanel; run;

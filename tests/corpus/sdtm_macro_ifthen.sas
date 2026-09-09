/* Arm-specific derivation selected by %IF in a macro */
%macro deriveflag(arm);
  data d;
    set vs;
    %if &arm = DRUG %then %do;
      flag = (AVAL > 130);
    %end;
    %else %do;
      flag = (AVAL > 140);
    %end;
  run;
%mend;
data vs; input AVAL; datalines;
120
135
145
;
run;
%deriveflag(DRUG)
proc print data=d; var AVAL flag; run;

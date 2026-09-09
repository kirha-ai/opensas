/* %NRSTR keeps &-text literal (not resolved) */
%macro showlit;
  %put NOTE: template is %nrstr(&subjid-&visit);
%mend;
%showlit
data d;
  msg = "generated";
run;
proc print data=d; run;

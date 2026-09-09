/* Generate a visit series for a subject with a %DO loop */
%macro genvisits(n);
  data vs;
    length USUBJID $8;
    USUBJID = "01-001";
    %do v = 1 %to &n;
      VISITNUM = &v;
      AVAL = 100 + &v * 5;
      output;
    %end;
  run;
%mend;
%genvisits(4)
proc print data=vs; var USUBJID VISITNUM AVAL; run;

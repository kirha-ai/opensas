/* Generate a subject roster with a %macro %do loop */
%macro gensubj(n);
  data dm;
    length USUBJID $8;
    %do i = 1 %to &n;
      USUBJID = "SUBJ-&i";
      AGE = 40 + &i;
      output;
    %end;
  run;
%mend;
%gensubj(3)
proc print data=dm; run;

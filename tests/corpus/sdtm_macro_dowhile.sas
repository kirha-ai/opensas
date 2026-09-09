/* Count triplings until a ceiling with %DO %WHILE */
%macro escalate;
  %let x = 1;
  %let steps = 0;
  %do %while (&x < 100);
    %let x = %eval(&x * 3);
    %let steps = %eval(&steps + 1);
  %end;
  data d; final = &x; steps = &steps; run;
%mend;
%escalate
proc print data=d; run;

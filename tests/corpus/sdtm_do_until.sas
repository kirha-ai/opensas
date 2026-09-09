/* Dose escalation until a ceiling (DO UNTIL) */
data titrate;
  x = 1;
  n = 0;
  do until (x >= 100);
    x = x * 3;
    n = n + 1;
  end;
run;
proc print data=titrate; var x n; run;

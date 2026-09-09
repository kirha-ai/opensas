/* Dose doubling with a bound + UNTIL exit (DO TO ... UNTIL) */
data titrate;
  x = 1;
  do i = 1 to 100 until (x > 50);
    x = x * 2;
  end;
  keep i x;
run;
proc print data=titrate; run;

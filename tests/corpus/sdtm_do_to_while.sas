/* Bounded loop with an extra WHILE guard (DO TO ... WHILE) */
data d;
  do i = 1 to 10 while (i * i < 30);
    sq = i * i;
    output;
  end;
  keep i sq;
run;
proc print data=d; run;

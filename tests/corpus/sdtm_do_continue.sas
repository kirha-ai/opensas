/* Skip odd iterations, keep even squares (DO + CONTINUE) */
data d;
  do i = 1 to 8;
    if mod(i, 2) = 1 then continue;
    sq = i * i;
    output;
  end;
  keep i sq;
run;
proc print data=d; run;

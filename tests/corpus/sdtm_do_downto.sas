/* Reverse-order countdown (DO ... BY -1) */
data d;
  do i = 5 to 1 by -1;
    rank = 6 - i;
    output;
  end;
  keep i rank;
run;
proc print data=d; run;

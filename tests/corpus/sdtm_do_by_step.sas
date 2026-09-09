/* Weekly visit days via DO ... BY step */
data sched;
  do day = 1 to 29 by 7;
    output;
  end;
run;
proc print data=sched; var day; run;

/* Find the first visit exceeding a threshold, then stop (DO + LEAVE) */
data vs; input USUBJID $ v1 v2 v3 v4; datalines;
01-001 118 122 141 150
01-002 120 125 128 130
;
run;
data firsthigh;
  set vs;
  array v{4} v1-v4;
  firstvisit = 0;
  do i = 1 to dim(v);
    if v{i} > 140 then do;
      firstvisit = i;
      leave;
    end;
  end;
  keep USUBJID firstvisit;
run;
proc print data=firsthigh; run;

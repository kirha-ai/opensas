/* Average only the non-missing readings (DO OVER + CONTINUE) */
data lb; input USUBJID $ r1 r2 r3; datalines;
01-001 10 . 30
01-002 . . 40
;
run;
data avg;
  set lb;
  array r{3} r1-r3;
  sm = 0;
  cnt = 0;
  do over r;
    if r = . then continue;
    sm = sm + r;
    cnt = cnt + 1;
  end;
  if cnt > 0 then mean = sm / cnt;
  keep USUBJID mean cnt;
run;
proc print data=avg; run;

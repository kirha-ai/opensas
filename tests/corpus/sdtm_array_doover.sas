/* Count high BP readings across visits (ARRAY + DO OVER) */
data vs;
  input USUBJID $ bp1 bp2 bp3;
  datalines;
01-001 120 125 130
01-002 140 135 138
;
run;
data flagged;
  set vs;
  array bps{3} bp1-bp3;
  high = 0;
  do over bps;
    if bps > 130 then high = high + 1;
  end;
  keep USUBJID high;
run;
proc print data=flagged; run;

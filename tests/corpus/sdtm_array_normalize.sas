/* Flag any out-of-range reading across visits (ARRAY over columns) */
data vs;
  input USUBJID $ v1 v2 v3;
  datalines;
01-001 120 125 155
01-002 118 122 128
;
run;
data flags;
  set vs;
  array vv{3} v1-v3;
  nhigh = 0;
  do i = 1 to dim(vv);
    if vv{i} > 140 then nhigh = nhigh + 1;
  end;
  keep USUBJID nhigh;
run;
proc print data=flags; run;

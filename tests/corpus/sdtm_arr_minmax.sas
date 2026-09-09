/* Per-subject min/max across visit columns (ARRAY scan) */
data vs;
  input USUBJID $ v1 v2 v3;
  datalines;
01-001 120 145 118
01-002 130 128 135
;
run;
data mm;
  set vs;
  array vv{3} v1-v3;
  vmax = vv{1};
  vmin = vv{1};
  do i = 2 to dim(vv);
    if vv{i} > vmax then vmax = vv{i};
    if vv{i} < vmin then vmin = vv{i};
  end;
  keep USUBJID vmin vmax;
run;
proc print data=mm; run;

/* Normalize each reading to 0..1 using array min/max then a second pass */
data vs; input USUBJID $ v1 v2 v3; datalines;
01-001 100 150 200
;
run;
data norm;
  set vs;
  array v{3} v1-v3;
  array n{3} n1-n3;
  lo = v{1}; hi = v{1};
  do i = 2 to dim(v);
    if v{i} < lo then lo = v{i};
    if v{i} > hi then hi = v{i};
  end;
  do i = 1 to dim(v);
    n{i} = round((v{i} - lo) / (hi - lo), 0.01);
  end;
  keep USUBJID n1 n2 n3;
run;
proc print data=norm; run;

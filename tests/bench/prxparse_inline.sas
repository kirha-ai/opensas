/* 1M-observation PRXPARSE inline benchmark. Print one checksum line. */
data source;
  length u $6;
  do i=1 to 1000000;
    u='abc123';
    output;
  end;
run;
data _null_;
  set source;
  retain hits 0;
  if prxmatch(prxparse('/abc/'), u) then hits+1;
  if _n_=1000000 then put hits=;
run;

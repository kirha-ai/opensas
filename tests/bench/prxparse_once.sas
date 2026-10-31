/* Same 1M observations as prxparse_inline; compile the pattern once. */
data source;
  length u $6;
  do i=1 to 1000000;
    u='abc123';
    output;
  end;
run;
data _null_;
  set source;
  retain re hits 0;
  if _n_=1 then re=prxparse('/abc/');
  if prxmatch(re, u) then hits+1;
  if _n_=1000000 then put hits=;
run;

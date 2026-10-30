/* Earlier dev2 probe: 1M calls in one DATA-step iteration, not 1M rows. */
data _null_;
  u='abc123';
  hits=0;
  do i=1 to 1000000;
    if prxmatch(prxparse('/abc/'), u) then hits+1;
  end;
  put hits=;
run;

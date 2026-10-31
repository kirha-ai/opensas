/* Parse-once control for prxparse_loop_inline.sas. */
data _null_;
  u='abc123';
  hits=0;
  re=prxparse('/abc/');
  do i=1 to 1000000;
    if prxmatch(re, u) then hits+1;
  end;
  put hits=;
run;

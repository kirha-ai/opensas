/* BUG-dolistmiss: a DO value-list must iterate a bare numeric-missing item.
   `do s=10,.,30;` runs THREE times (10, ., 30) — `.` is a legitimate single
   value, not a malformed range that gets skipped. */
data _null_;
  n=0;
  do s = 10, ., 30;
    n+1;
    put "iter " n "s=" s;
  end;
  put "total_iters=" n;
run;

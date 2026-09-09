data _null_;
  /* terminal index overshoots the stop by one BY step (SAS 9.4) */
  do i = 1 to 5; end;
  put "term_i=" i;
  do j = 10 to 1 by -3; end;
  put "term_j=" j;
  /* the stop bound is evaluated ONCE at entry: mutating n mid-loop
     does NOT change the iteration count (SAS 9.4) */
  n = 3; cnt = 0;
  do k = 1 to n;
    n = 100;
    cnt + 1;
  end;
  put "boundonce_iters=" cnt " term_k=" k;
run;

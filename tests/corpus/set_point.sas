/* QA regression (BUG-setpoint fixed): SET point= direct/random access, incl the
   canonical do i=1 to nobs; set b point=i nobs=n; loop. */
data b; input x; datalines;
30
40
50
;
run;
data _null_;
  do i=1 to n;
    set b point=i nobs=n;
    put "i=" i " x=" x;
  end;
  stop;
run;

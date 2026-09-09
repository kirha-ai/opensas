%let a = 3;
%let b = 4;
%macro addit(x, y);
  data _null_;
    s = &x + &y;
    put "s=" s;
  run;
%mend;
%addit(&a, &b)

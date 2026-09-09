data _null_;
  p=1; q=2; r=3;
  do i = 1 to 6;
    call allperm(i, p, q, r);
    put p q r;
  end;
run;

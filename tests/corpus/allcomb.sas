data _null_;
  a=1; b=2; c=3;
  do i = 1 to 3;
    call allcomb(i, 2, a, b, c);
    put a b;
  end;
run;

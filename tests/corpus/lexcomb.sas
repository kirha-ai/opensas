data _null_;
  a=10; b=20; c=30; d=40;
  do i = 1 to 6;
    call lexcomb(i, 2, a, b, c, d);
    put a b;
  end;
run;

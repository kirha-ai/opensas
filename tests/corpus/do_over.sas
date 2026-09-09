/* FEAT-doover: DO OVER implicit array iteration (SAS 9.4 DO-statement doc:
   "DO OVER array-name" iterates LBOUND..HBOUND with an implicit index; the
   bare array name in the body refers to the current element). Covers a plain
   sum, explicit {lo:hi} bounds, and do-over nested inside another DO loop
   over two arrays. */
data _null_;
  array a{3} a1-a3 (5 10 15);
  s = 0;
  do over a;
    s + a;
  end;
  put "sum=" s;

  array b{2:4} b2-b4 (100 200 300);
  t = 0;
  do over b;
    t + b;
  end;
  put "bounded=" t;

  array x{2} x1-x2 (1 2);
  array y{2} y1-y2 (10 20);
  total = 0;
  do i = 1 to 2;
    do over x;
      total + x;
    end;
    do over y;
      total + y;
    end;
  end;
  put "nested=" total;
run;

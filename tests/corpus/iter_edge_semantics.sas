/* tick241 pin: DATA-step iteration semantics around DO loops and arrays.
   - index after normal completion = first value past the bound; after LEAVE =
     leave-time value; never-entered TO loop leaves index at start value
   - LEAVE/CONTINUE act on the innermost loop only
   - _temporary_ array inits once and accumulates across iterations
   - nested array subscripts and non-integer subscript truncation */
data _null_;
  do i = 1 to 3;
  end;
  put "normal " i;
  do j = 1 to 10;
    if j = 4 then leave;
  end;
  put "leave  " j;
  do m = 3 to 1;
  end;
  put "empty  " m;
run;

data _null_;
  do i = 1 to 2;
    do j = 1 to 4;
      if j = 2 then continue;
      if j = 4 then leave;
      put "i=" i " j=" j;
    end;
  end;
run;

data _null_;
  array t{3} _temporary_ (10 20 30);
  input x;
  t{1} + x;
  put t{1} t{2} t{3};
  datalines;
1
2
;
run;

data _null_;
  array a{5} (10 20 30 40 50);
  array b{2} (2 4);
  k = 2.9;
  put a{b{1}} a{b{2}} a{k};
run;

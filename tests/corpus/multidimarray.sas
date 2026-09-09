/* GAP-multidimarray: multidimensional arrays. SAS 9.4: "the number of elements
   is the product of the dimensions; the rightmost subscript varies fastest"
   (row-major). Element access m{i,j} maps to a flat member; dim/lbound/hbound take
   an optional dimension index. Synthesized (no PHI). */
data t;
  array m{2,3} m1-m6;

  /* fill row-major with i*10 + j via nested loops */
  do i = 1 to dim(m,1);
    do j = 1 to dim(m,2);
      m{i,j} = i*10 + j;
    end;
  end;

  /* sum the whole array two ways: nested loop and `of m{*}` */
  tot = 0;
  do i = lbound(m,1) to hbound(m,1);
    do j = lbound(m,2) to hbound(m,2);
      tot + m{i,j};
    end;
  end;
  star = sum(of m{*});
  d1 = dim(m,1);
  d2 = dim(m,2);

  put "m11=" m1 " m23=" m6 " tot=" tot " star=" star;
  put "d1=" d1 " d2=" d2;
run;

/* non-1 lower bounds per dimension */
data g;
  array a{0:1, 5:7} a1-a6;
  a{0,5} = 100;   /* first element */
  a{1,7} = 600;   /* last element  */
  lo1 = lbound(a,1); hi1 = hbound(a,1);
  lo2 = lbound(a,2); hi2 = hbound(a,2);
  put "a05=" a1 " a17=" a6;
  put "lo1=" lo1 " hi1=" hi1 " lo2=" lo2 " hi2=" hi2;
  keep a1 a6 lo1 hi1 lo2 hi2;
run;

proc print data=g noobs; run;

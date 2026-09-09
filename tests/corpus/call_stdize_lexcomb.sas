/* QA regression: CALL STDIZE (standardize: (x-mean)/std, sample n-1) and
   CALL LEXCOMB (lexicographic combinations). dev2 89a5231. */
data _null_;
  x1=2; x2=4; x3=6;
  call stdize(x1, x2, x3);
  put "stdize=" x1 x2 x3;
run;
data _null_;
  c1=1; c2=2; c3=3; c4=4;
  do i = 1 to 6;
    call lexcomb(i, 2, c1, c2, c3, c4);
    put "lexcomb" i "=" c1 c2;
  end;
run;

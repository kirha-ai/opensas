/* A macro var drives an ARRAY dimension and a DO bound in the DATA step (compile-time
   text substitution into numeric context). corpus-macroedge. */
%let n = 4;
data _null_;
  array a[&n] _temporary_;
  sumsq = 0;
  do i = 1 to &n;
    a[i] = i * i;
    sumsq + a[i];
  end;
  put "n=&n sumsq=" sumsq;
run;

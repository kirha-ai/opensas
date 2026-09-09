%macro inner(x);
  data _null_;
    put "inner &x";
  run;
%mend;

%macro outer(n);
  %inner(&n)
  data _null_;
    put "outer &n";
  run;
%mend;

%outer(5)

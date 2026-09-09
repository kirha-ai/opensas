%macro inner(v);
    put "v=&v";
%mend;
%macro outer(a, b);
  data _null_;
    %inner(&a)
    %inner(&b)
  run;
%mend;
%outer(1, 2)

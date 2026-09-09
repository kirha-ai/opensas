/* Outer passes its &param to an inner macro that %evals an expression built from it. corpus-macroedge. */
%macro sq(v);
  %let r = %eval(&v * &v);
  data _null_; put "sq(&v)=&r"; run;
%mend;
%macro drive(base);
  %sq(&base)
  %sq(%eval(&base + 1))
%mend;
%drive(6)

/* CALL SOFTMAX (exp(xi)/Σexp(xj) in place) and CALL VNEXT (iterate PDV variable
   names/type/length). Phase-F-callbatch.
   Re-pinned for BUG-varorder: the assignments establish x1-x3 BEFORE the LENGTH
   statement, so SAS PDV order is x1 x2 x3 nm ty and VNEXT iterates from x1 —
   the old nm-first expectation encoded the pre-fix always-LENGTH-first bug. */
data _null_;
  x1=1; x2=2; x3=3;
  call softmax(x1, x2, x3);
  put "softmax=" x1 8.5 " " x2 8.5 " " x3 8.5;
  length nm $32 ty $1;
  call vnext(nm, ty, ln); put "v1=" nm " " ty " " ln;
  call vnext(nm, ty, ln); put "v2=" nm " " ty " " ln;
run;

/* Multi-key BY first./last.: inner key (b) resets on every outer (a) change,
   even when the inner VALUE repeats across the boundary. first.a implies
   first.b; a single-obs group has both flags 1. (tick217 audit — locks the
   verified-correct multi-key reset semantics.) */
data have;
  input a b;
  datalines;
1 5
1 5
1 9
2 5
3 7
;
run;
data _null_;
  set have;
  by a b;
  put a= b= "| Fa=" first.a " La=" last.a " Fb=" first.b " Lb=" last.b;
run;

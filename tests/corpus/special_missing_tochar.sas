* GH#57 ISS-specialmiss-tochar: special missing (.A-.Z, ._) keeps its letter
  when coerced num->char via PUT() function and automatic num->char conversion.
  Plain missing (.) stays ".", and a real number is unaffected.;
data _null_;
  x = .K;
  u = ._;
  p = .;
  length pf uf plf nf ac $12;
  pf  = put(x, best12.);   /* PUT() function */
  uf  = put(u, best12.);
  plf = put(p, best12.);
  nf  = put(3.5, best12.);
  ac  = compress(x);       /* function-arg num->char coercion */
  cc  = "[" || x || "]";   /* concat auto num->char coercion */
  put "put_fn=[" pf "]";
  put "underscore=[" uf "]";
  put "plain=[" plf "]";
  put "normal=[" nf "]";
  put "autoconv=[" ac "]";
  put "concat=" cc;
run;

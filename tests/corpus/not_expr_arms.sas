/* EBNF-gate tick356 marker evidence — not_expr prefix arms NOT | "^" | "~" |
   "¬" (Language Reference: Concepts Table 6.6): every spelling negates the compare_expr it prefixes;
   `¬` lexes to the caret token (fixture expr_alt_ops landed that). */
data _null_;
  a = not (1=2);  b = ^(1=1);  c = ~(0);  d = ¬(5);
  e = (not 0) and (¬0) and (^0) and (~0);
  put a= b= c= d= e=;
  if ¬(1=2) then put "notsign ok";
run;

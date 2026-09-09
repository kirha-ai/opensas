/* VLENGTH / VLENGTHX: DECLARED (allocated) storage length — distinct from LENGTH's
   trimmed value width. Numeric=8. Regression guard for BUG-vlength. Phase-F. */
data _null_;
  length a $ 20 b $ 5;
  a = "hi";
  b = "x";
  la = vlength(a);
  lb = vlength(b);
  lax = vlengthx("a");
  lgt = length(a);
  ln = vlength(42);
  lit = vlength("hello");
  put "vlength_a=" la;
  put "vlength_b=" lb;
  put "vlengthx_a=" lax;
  put "length_a=" lgt;
  put "vlength_num=" ln;
  put "vlength_lit=" lit;
run;

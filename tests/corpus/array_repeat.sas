/* ARRAY initial-value REPEAT factor: n*value = n copies of value (BUG-arrayrepeat) */
data _null_;
  array a{5} a1-a5 (3 * 0 1 2);
  put "a=" a1 a2 a3 a4 a5;
  array b{5} b1-b5 (2*10 3*20);
  put "b=" b1 b2 b3 b4 b5;
  array c{3} c1-c3 (3*1);
  put "c=" c1 c2 c3;
  array d{4} d1-d4 (1 2 3 4);
  put "d=" d1 d2 d3 d4;
run;

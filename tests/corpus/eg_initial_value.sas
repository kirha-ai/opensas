data _null_;
  array a{3} a1-a3 (10 20 30);
  retain running 0;
  running + a2;
  put "array_init=" a1 a2 a3 " retain_init_accum=" running;
run;

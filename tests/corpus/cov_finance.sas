data _null_;
  m=mort(1000, ., 0.01, 12);
  ir=irr(1, -100, 110);
  np=npv(10, 1, -100, 110);
  put "mort=" m;
  put "irr=" ir;
  put "npv=" np;
run;

data _null_;
  m1=atan(1); m2=divide(10,4); m3=fuzz(1.99999999999); m4=compound(1000,.,0.05,3);
  put "atan=" m1;
  put "divide=" m2;
  put "fuzz=" m3;
  put "compound=" m4;
run;

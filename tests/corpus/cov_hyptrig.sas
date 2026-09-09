data _null_;
  pi=constant('pi');
  s1=sec(0); s2=csc(pi/2); s3=cot(pi/4);
  h1=arcosh(1); h2=arsinh(0); h3=artanh(0);
  put "sec_csc_cot=" s1 s2 s3;
  put "arcosh_arsinh_artanh=" h1 h2 h3;
run;

data _null_;
  name='Bob'; n=7;
  d = mdy(6,15,2021);
  put name= n=;
  put @10 name;
  put "d=" d date9.;
  put name / n;
run;

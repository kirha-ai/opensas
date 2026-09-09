data _null_;
  d = mdy(7, 4, 2020);
  put d date9.;
  put d date7.;
  put d mmddyy10.;
  put d mmddyy8.;
run;

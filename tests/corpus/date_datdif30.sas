data _null_;
  d1 = mdy(1, 31, 2020);
  d2 = mdy(3, 31, 2020);
  dd = datdif(d1, d2, '30/360');
  put "dd=" dd;
run;

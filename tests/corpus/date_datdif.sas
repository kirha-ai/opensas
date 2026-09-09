data _null_;
  d1 = mdy(1, 1, 2020);
  d2 = mdy(3, 1, 2020);
  dd = datdif(d1, d2, 'act/act');
  put "dd=" dd;
run;

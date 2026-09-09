data ae;
  length subjid $4;
  input subjid $ ry rm rd ay am ad;
  datalines;
S001 2020 1 1 2020 1 1
S001 2020 1 1 2020 1 15
S001 2020 1 1 2019 12 25
;
run;
data _null_;
  set ae;
  rfst = mdy(rm, rd, ry);
  aedt = mdy(am, ad, ay);
  if aedt >= rfst then dy = aedt - rfst + 1;
  else dy = aedt - rfst;
  put subjid "aedy=" dy;
run;

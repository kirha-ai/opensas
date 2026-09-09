data _null_;
  jd = juldate('31dec99'd);
  jd2 = juldate('01jan2099'd);
  j7 = juldate7('01jan2020'd);
  dj = datejul(2020001);
  nw = nwkdom(3, 1, 1, 2020);
  put "jd=" jd " jd2=" jd2 " j7=" j7;
  put "dj=" dj " nw=" nw;
run;

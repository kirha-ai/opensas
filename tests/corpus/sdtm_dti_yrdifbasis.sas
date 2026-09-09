/* YRDIF under ACT/ACT, 30/360, and AGE bases */
data d;
  b = "15JUN1980"d;
  r = "15JAN2024"d;
  actact = round(yrdif("01JAN2020"d, "01JUL2020"d, "ACT/ACT"), 0.0001);
  d30360 = yrdif("01JAN2020"d, "01JUL2020"d, "30/360");
  age    = floor(yrdif(b, r, "AGE"));
run;
proc print data=d; var actact d30360 age; run;

data src;
  input g x @@;
  datalines;
1 10 1 20 1 30 2 5 2 15
;
run;

data _null_;
  set src;
  by g;
  retain tot;
  if first.g then tot = 0;
  tot + x;
  d = dif(x);
  if first.g then d = .;
  l2 = lag2(x);
  put g= x= tot= d= l2= first.g= last.g=;
run;

data _null_;
  d1 = "01JAN2020"d;
  d2 = "15MAR2021"d;
  mo = intck("month", d1, d2);
  qt = intck("qtr",   d1, d2);
  wk = intck("week",  "01JAN2020"d, "31JAN2020"d);
  wd = intck("weekday","01JAN2020"d,"31JAN2020"d);
  nx = intnx("month", d1, 5);
  dd = datdif(d1, d2, "30/360");
  put mo= qt= wk= wd= nx= date9. dd=;

  do zz = -5, 0, 15, 55, 150;
    select;
      when (zz < 0)        band = "neg ";
      when (0 <= zz < 10)  band = "low ";
      when (10 <= zz < 100) band = "mid ";
      otherwise            band = "high";
    end;
    put zz= band=;
  end;
run;

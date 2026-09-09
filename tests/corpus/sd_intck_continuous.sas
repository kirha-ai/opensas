data _null_;
  yd = intck('year', mdy(6,1,2019), mdy(3,1,2020));
  yc = intck('year', mdy(6,1,2019), mdy(3,1,2020), 'c');
  md = intck('month', mdy(1,20,2020), mdy(3,5,2020));
  mc = intck('month', mdy(1,20,2020), mdy(3,5,2020), 'c');
  put "year_discrete=" yd " year_cont=" yc;
  put "month_discrete=" md " month_cont=" mc;
run;

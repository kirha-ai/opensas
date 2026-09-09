data _null_;
  ds = input('2023-01-01', yymmdd10.);
  de = input('2023-01-22', yymmdd10.);
  call IS8601_CONVERT('dt/dt','du', dhms(ds,0,0,0), dhms(de,0,0,0), dur);
  put 'DUR=' dur;
run;

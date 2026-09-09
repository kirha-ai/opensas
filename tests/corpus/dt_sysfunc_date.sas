%let d = %sysfunc(mdy(3,15,2020));
%let s = %sysfunc(putn(&d, date9.));
%let nx = %sysfunc(intnx(month, &d, 1, b));
%let sn = %sysfunc(putn(&nx, date9.));
data _null_;
  put "sysfunc_date=&s";
  put "sysfunc_nextmonth=&sn";
run;

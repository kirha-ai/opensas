data d;
  input name $ age;
  datalines;
Al 14
Bo 63
Cy 12
;
run;

proc sql;
  create table t as
    select name, case when age > 60 then 'old' end as flag from d;
quit;

data _null_;
  set t;
  if flag = '' then f = 'blank'; else f = flag;
  put "name=" name " flag=" flag " f=" f;
run;

proc sql;
  select name from t where flag = '';
quit;

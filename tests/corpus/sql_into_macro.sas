data vars;
  length name $8;
  input name $ n;
  datalines;
AGE 30
SEX 1
RACE 2
;
run;
proc sql;
  select count(*) into :cnt from vars;
  select max(n) into :mx from vars;
  select name into :namelist separated by ' ' from vars;
  select max(n), min(n) into :hi, :lo from vars;
  select n into :n1-:n3 from vars;
quit;
data _null_;
  length nl $30;
  c = &cnt;
  m = &mx;
  nl = "&namelist";
  put "count=" c "max=" m;
  put "keeplist=" nl;
  put "hilo=&hi &lo";
  put "range=&n1 &n2 &n3";
run;

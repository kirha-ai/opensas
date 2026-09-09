/* Derive BMI then filter overweight subjects via CALCULATED in WHERE (SQL) */
data vs;
  input USUBJID $ WEIGHT HEIGHT;
  datalines;
01-001 70 1.75
01-002 90 1.80
01-003 55 1.60
;
run;
proc sql;
  select USUBJID, WEIGHT / (HEIGHT * HEIGHT) as bmi
  from vs
  where calculated bmi >= 25
  order by USUBJID;
quit;

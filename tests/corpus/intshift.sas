/* QA regression: INTSHIFT (dev2 8824ba3) — shift interval of a base interval,
   verified exact vs SAS doc p.1105 examples (ignores multiples/shift indexes). */
data _null_;
  a=intshift("year"); b=intshift("dtyear"); c=intshift("minute");
  d=intshift("qtr"); e=intshift("dttenday"); f=intshift("weekday5.4");
  put "year=" a;
  put "dtyear=" b;
  put "minute=" c;
  put "qtr=" d;
  put "dttenday=" e;
  put "weekday=" f;
run;

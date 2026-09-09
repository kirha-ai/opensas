data lb;
  input usubjid $ aval;
  datalines;
S01 5
S02 15
S03 25
;
run;
data _null_;
  set lb end=last nobs=total;
  sumval + aval;
  if last then do;
    mean = sumval / total;
    put "n=" total "sum=" sumval "mean=" mean;
  end;
run;

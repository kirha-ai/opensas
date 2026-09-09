data ex;
  length trt $1;
  input trt $ dose age;
  datalines;
A 10 45
A 20 60
B 10 30
B 20 70
;
run;
data sel;
  set ex;
  where (trt = 'A' or dose = 20) and not (age < 40);
run;
proc print data=sel noobs; run;

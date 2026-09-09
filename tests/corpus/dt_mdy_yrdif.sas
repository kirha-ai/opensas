data ages;
  length subjid $4;
  input subjid $ by bm bd vy vm vd;
  datalines;
S001 1980 5 15 2020 6 1
S002 1965 12 31 2020 1 1
S003 2000 2 29 2020 3 1
;
run;
data _null_;
  set ages;
  birth = mdy(bm, bd, by);
  visit = mdy(vm, vd, vy);
  age = floor(yrdif(birth, visit, 'act/act'));
  put subjid "age=" age;
run;

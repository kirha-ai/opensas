data pts; length subjid $4; input subjid $ by bm bd; datalines;
S001 1980 3 15
S002 1980 9 1
S003 2000 1 1
;
run;
data _null_;
  set pts;
  ref = mdy(3,1,2020);
  birth = mdy(bm, bd, by);
  age_intck = intck('year', birth, ref, 'c');
  age_yrdif = floor(yrdif(birth, ref, 'act/act'));
  put subjid "age_intck=" age_intck "age_yrdif=" age_yrdif;
run;

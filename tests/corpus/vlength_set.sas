data d;
  length name $20 code $5;
  input name $ code $;
  datalines;
Alice A1
Bob B22
;
run;
data _null_;
  set d;
  ln = vlength(name);
  lc = vlengthx("code");
  put "name=" name " vlength=" ln;
  put "code=" code " vlengthx=" lc;
run;

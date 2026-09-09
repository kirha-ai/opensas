data have;
  input grp v;
  datalines;
1 10
1 20
2 30
1 40
1 50
;
run;

data _null_;
  set have;
  by grp notsorted;
  if first.grp then put "FIRST grp=" grp;
  put "row grp=" grp " v=" v;
  if last.grp  then put "LAST grp="  grp;
run;

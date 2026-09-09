data have;
  input grp t y keepme;
  datalines;
1 1 10 999
1 2 20 999
2 1 30 777
;
run;

proc transpose data=have out=w prefix=V;
  by grp;
  var y;
  copy keepme;
run;

data _null_;
  set w;
  put grp= _name_= V1= V2= keepme=;
run;

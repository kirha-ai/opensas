data a; input id x; datalines;
1 10
2 20
;
run;
data b; input id y; datalines;
1 100
2 200
;
run;
data c; input id z; datalines;
1 1000
2 2000
;
run;
proc sql;
  create table j1 as select a.x, b.y from a, b where a.id=b.id;
  create table j2 as select a.id, x, y, z from a join b on a.id=b.id join c on a.id=c.id;
quit;
data _null_; set j1; put "comma " x= y=; run;
data _null_; set j2; put "three " id= x= y= z=; run;

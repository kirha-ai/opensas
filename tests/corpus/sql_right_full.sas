data a;
  input id x;
  datalines;
1 10
2 20
3 30
;
run;
data b;
  input id y;
  datalines;
2 200
3 300
4 400
;
run;
proc sql;
  create table r as select a.id as aid, x, b.id as bid, y from a right join b on a.id = b.id order by bid;
  create table f as select a.id as aid, x, b.id as bid, y from a full join b on a.id = b.id order by aid, bid;
quit;
data _null_; set r; put "R aid=" aid " x=" x " bid=" bid " y=" y; run;
data _null_; set f; put "F aid=" aid " x=" x " bid=" bid " y=" y; run;

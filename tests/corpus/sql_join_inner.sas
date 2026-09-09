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
  create table j as
    select a.id, a.x, b.y
    from a inner join b on a.id = b.id
    order by a.id;
quit;

data _null_;
  set j;
  put "id=" id " x=" x " y=" y;
run;

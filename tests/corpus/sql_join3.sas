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
1 100
2 200
3 300
;
run;
data c;
  input id z;
  datalines;
1 1000
2 2000
3 3000
;
run;

proc sql;
  create table j as
    select a.id, x, y, z
    from a inner join b on a.id = b.id
           inner join c on a.id = c.id
    order by a.id;
quit;

data _null_;
  set j;
  put "id=" id " x=" x " y=" y " z=" z;
run;

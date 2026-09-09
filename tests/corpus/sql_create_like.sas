/* CREATE TABLE ... LIKE clones the column structure as an empty table; a
   subsequent INSERT ... SELECT (columns in physical order) then populates it.
   Boundary: LIKE structural clone + insert-from-select round-trip. */
data src;
  input id qty amt;
  datalines;
1 10 100
2 20 200
3 30 300
;
run;
proc sql;
  create table clone like src;
  insert into clone select id, qty, amt from src where qty >= 20;
  select id, qty, amt from clone order by id;
quit;

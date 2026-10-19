/* BUG-sqlorderbyambig (GH#26): ORDER BY an unqualified column that lives in
   BOTH sides of a join, where the SELECT list projects exactly ONE of them.
   `select a.id … order by id` names the OUTPUT column `id` — ORDER BY
   resolves result columns before contributing tables — so live SAS 9.4 runs
   it; opensas rejected it as an ambiguous reference. The fix exempts a bare
   ORDER BY name that matches exactly one output column (uniqueOutputCol in
   sql.zig); asc/desc and the listing path are both pinned here. The
   two-projections edge (`select a.id, b.id`) stays an ERROR — pinned in
   sql_order_ambigshared_both.sas. Invented data (D-011). */
data a;
  input id x;
  datalines;
2 20
1 10
3 30
;
run;
data b;
  input id y;
  datalines;
2 200
3 300
1 100
;
run;

/* the repro shape: id is in both tables, projected once (a.id) */
proc sql;
  create table t as select a.id, a.x, b.y from a inner join b on a.id=b.id order by id;
quit;

data _null_;
  set t;
  put "asc id=" id "x=" x "y=" y;
run;

proc sql;
  create table t2 as select a.id, a.x, b.y from a inner join b on a.id=b.id order by id desc;
quit;

data _null_;
  set t2;
  put "desc id=" id "x=" x "y=" y;
run;

/* control: the listing path (no create table) resolves the same way */
proc sql;
  title 'listing';
  select a.id, b.y from a inner join b on a.id=b.id order by id;
quit;

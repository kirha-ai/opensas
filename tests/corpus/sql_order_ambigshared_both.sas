/* BUG-sqlorderbyambig (GH#26), PRECISION edge: the ORDER BY exemption is a
   UNIQUE output-name check, not mere existence. Project BOTH same-named
   columns (`select a.id, b.id … order by id`) and the bare name again has two
   candidates — SAS 9.4 still errors "Ambiguous reference, column id is in
   more than one table." So does opensas, before and after the fix. The
   positive control above the failing step proves the neighbour stays green.
   Invented data (D-011).
   expect-rc: 1 */
data a;
  input id x;
  datalines;
2 20
1 10
;
run;
data b;
  input id y;
  datalines;
2 200
1 100
;
run;

/* positive control: one projection of the shared name — runs clean (rc 0
   would be this step alone; the ERROR below sets the script's rc) */
proc sql;
  create table t as select a.id, a.x, b.y from a inner join b on a.id=b.id order by id;
quit;

data _null_;
  set t;
  put "control id=" id "x=" x "y=" y;
run;

/* the edge: two output columns named id — still the ambiguous reference */
proc sql;
  create table bad as select a.id, b.id from a inner join b on a.id=b.id order by id;
quit;

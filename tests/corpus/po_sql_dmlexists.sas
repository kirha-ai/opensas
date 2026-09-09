/* BUG-sqldmlexists: EXISTS / NOT EXISTS in a DELETE or UPDATE WHERE was never
   substituted, so the DML matched zero rows (silent no-op). Both correlated
   forms below must affect exactly the matching rows. */
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
;
run;
data c;
  input id x;
  datalines;
1 10
2 20
3 30
;
run;
data d;
  input id y;
  datalines;
2 0
;
run;
proc sql;
  /* correlated DELETE: drop a-rows that have a matching b-row -> keep id=1 */
  delete from a where exists (select 1 from b where b.id = a.id);
  /* correlated UPDATE: bump only c-rows with a matching d-row -> id=2 */
  update c set x = 999 where exists (select 1 from d where d.id = c.id);
quit;
proc print data=a noobs; run;
proc print data=c noobs; run;

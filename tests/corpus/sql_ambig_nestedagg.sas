/* BUG-sqlambigcol + BUG-sqlnestedagg: the VALID cases stay correct.
   Ambiguous bare join keys and nested aggregates fail loud (tested in-file);
   here we prove the legitimate neighbours are byte-identical. */
data a; input k x; datalines;
1 10
2 20
;
run;
data b; input k y; datalines;
2 200
3 300
;
run;
proc sql;
  /* coalesced (qualified) key on a FULL join keeps every row's key */
  title 'coalesced full join';
  select coalesce(a.k,b.k) as k, x, y from a full join b on a.k=b.k order by k;
quit;
proc sql;
  /* an unqualified column present in exactly ONE table stays legal */
  title 'unambiguous unqualified column';
  select x, y from a join b on a.k=b.k;
quit;
data t; input v aa bb; datalines;
5 1 2
10 3 4
;
run;
proc sql;
  /* non-nested aggregates: unaffected by the nested-agg guard */
  title 'non-nested aggregates';
  select sum(v) as s, max(v) as m, sum(aa*bb) as p from t;
quit;

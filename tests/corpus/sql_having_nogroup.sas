/* BUG-sqlhavingnogroup: a non-star HAVING with no GROUP BY and no aggregate of
   its own routed to the row-wise path, which never looked at q.having — the
   predicate was silently dropped and every row came back. SAS 9.4 treats it as
   a per-row filter (like WHERE). An aggregate inside a HAVING subquery is the
   subquery's own — the outer query is still per-row. avg(sal)=250, so both
   queries keep only the two above-250 rows. */
data t;
  input dept $ sal;
  datalines;
a 100
a 300
b 200
b 400
;
run;
proc sql;
  select dept, sal from t having sal > 250;
quit;
proc sql;
  select dept, sal from t having sal > (select avg(sal) from t);
quit;

/* BUG-sqlhavingsubq: a scalar subquery in HAVING used to parse-error and then
   silently keep every group. Now it collapses to its value and filters. Groups
   whose sum exceeds the overall avg (33.75) survive: only C. */
data s;
  input g $ v;
  datalines;
A 10
A 20
B 5
C 100
;
run;
proc sql;
  select g, sum(v) as tot
  from s
  group by g
  having sum(v) > (select avg(v) from s);
quit;

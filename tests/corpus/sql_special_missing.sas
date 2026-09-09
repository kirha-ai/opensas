/* BUG-sqlmissdistinct: special missings are DISTINCT values in SAS — SQL
   DISTINCT/GROUP BY/UNION merged .A into . (any-NaN-equals-any-NaN), and the
   result printer showed "." instead of the letter. DATA-side twin (hash keys,
   MERGE BY) is exec.zig — ticketed to dev-d. */
data a; input k v; datalines;
.A 1
.Z 2
._ 3
.A 4
;
run;
proc sql;
  select k, v from a;
  select distinct k from a;
  select k, count(*) as n from a group by k;
  select k from a order by k;
  select k from a where k = .A;
quit;

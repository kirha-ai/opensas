/* BUG-sqlexprdetailremerge: a non-summarized detail column referenced INSIDE an
   expression (sal in sal/sum(sal)) under GROUP BY must trigger SAS remerge —
   broadcast each group's aggregate across its detail rows → N rows (percent-of-
   group idiom), not 1 row/group. Sibling of BUG-sqlgroupremerge (bare detail col).
   Guards the two collapse cases too: a pure aggregate select, and an expression
   over only the GROUP BY key, both still collapse to 1 row/group. */
data t;
  input dept $ sal;
  datalines;
A 100
A 300
B 200
B 200
;
run;
proc sql;
  /* remerge: expression detail → one row per input row */
  select dept, sal, sal/sum(sal) as frac from t group by dept;
  /* collapse: pure aggregate, no detail → one row per group */
  select dept, sum(sal) as tot from t group by dept;
  /* collapse: expression over only the group key → one row per group */
  select dept, count(*)/count(*) as one from t group by dept;
quit;

/* BUG-sqlgroupnoagg: a GROUP BY with no summary function anywhere in the query
   must act as ORDER BY (all rows, ordered by the group keys — not one arbitrary
   row per group); an aggregate appearing ONLY in HAVING must still trigger
   grouping/remerge. */
data emp;
  input id name $ dept sal;
  datalines;
1 ann 10 100
2 bob 10 200
3 cid 20 300
4 dan 20 500
;
run;
proc sql;
  /* no summary function anywhere: all 4 rows, ordered by dept */
  select name, dept from emp group by dept;
  /* aggregate only in HAVING: depts with more than one row */
  select dept from emp group by dept having count(*) > 1;
  /* HAVING aggregate + detail columns: remerge — rows above their dept mean */
  select id, dept, sal from emp group by dept having sal > avg(sal);
quit;

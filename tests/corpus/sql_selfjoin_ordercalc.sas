/* doc-finder tick169 verified-clean lock: reflexive self-join + ORDER BY
   CALCULATED <alias> DESC with a secondary key. SAS 9.4 SQL Procedure:
   a self-join lists the same table twice under different aliases; ORDER BY
   CALCULATED names a computed SELECT column; ties break by the next key. */
data emp;
  input id mgr sal;
  datalines;
1 3 100
2 3 200
3 . 300
4 1 150
;
run;
proc sql;
  select a.id, b.sal as mgrsal, b.sal - a.sal as diff
  from emp a, emp b
  where a.mgr = b.id
  order by calculated diff desc, a.id;
quit;

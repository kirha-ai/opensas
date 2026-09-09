data one; input k v; datalines;
1 100
2 200
;
run;
data two; input k w; datalines;
1 10
2 20
;
run;
proc sql;
  select p.v, q.w from one p join two q on p.k=q.k;
quit;
proc sql;
  select a.v as av, b.v as bv from one a join one b on a.k=b.k;
quit;

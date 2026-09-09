data t;
  input id x;
  datalines;
1 10
2 20
3 30
4 40
;
run;
proc sql;
  insert into t values(5,50);
  update t set x=x*2 where id in (2,3);
  delete from t where id=1;
quit;
proc print data=t noobs; run;

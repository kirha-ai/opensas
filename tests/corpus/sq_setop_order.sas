data q1; input v; datalines;
30
10
;
run;
data q2; input v; datalines;
20
40
;
run;
proc sql;
  create table sorted as
    select v from q1 union select v from q2 order by v desc;
quit;
proc print data=sorted noobs; run;

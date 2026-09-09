data a; input id x; datalines;
1 10
2 20
;
run;
/* CREATE TABLE LIKE: empty table with the same columns */
proc sql; create table c like a; quit;
proc sql; insert into c values(9, 90); quit;
proc print data=c noobs; run;
/* ALTER TABLE ADD / DROP */
proc sql;
  alter table a add z num, w char(4);
  alter table a drop x;
  select * from a;
quit;

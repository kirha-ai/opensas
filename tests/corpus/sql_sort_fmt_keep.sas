/* GH#49: an attached FORMAT must survive PROC SQL create-table (select *,
   group/having) and PROC SORT out=, just like the DATA-step SET keeps it. */
proc format;
  value agrel 1='RELATED' 2='NOT RELATED';
run;
data a;
  input id x;
  format x agrel.;
  datalines;
1 2
1 1
2 2
;
run;
proc contents data=a; run;                 /* baseline: x has format AGREL */

proc sql; create table b as select * from a; quit;
proc contents data=b; run;                 /* select * keeps AGREL */

proc sql; create table c as select id, x from a group by id having x = min(x); quit;
proc contents data=c; run;                 /* group/having keeps AGREL */

proc sort data=a out=d; by id; run;
proc contents data=d; run;                 /* sort out= keeps AGREL */

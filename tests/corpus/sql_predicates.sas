data have;
  input v s $;
  datalines;
5 apple
15 banana
25 cherry
. date
;
run;

proc sql;
  create table b as select v from have where v between 10 and 20;
  create table l as select s from have where s like 'b%';
  create table n as select s from have where v is null;
  create table c as select s from have where s contains 'err';
quit;

data _null_; set b; put "b=" v; run;
data _null_; set l; put "l=" s; run;
data _null_; set n; put "n=" s; run;
data _null_; set c; put "c=" s; run;

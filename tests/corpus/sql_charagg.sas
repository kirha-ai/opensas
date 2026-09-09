data have;
  input name $;
  datalines;
Charlie
Alice
Bob
;
run;

proc sql;
  select min(name) as lo, max(name) as hi
  from have;
quit;

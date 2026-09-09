data have;
  input g $ h $;
  datalines;
A X
A Y
B X
B X
;
run;

proc freq data=have;
  tables g*h;
run;

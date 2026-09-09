data have;
  input grp $;
  datalines;
A
A
B
B
B
;
run;

proc freq data=have;
  tables grp;
run;

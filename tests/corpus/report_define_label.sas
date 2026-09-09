data have;
  input dept $ amt;
  datalines;
A 100
A 200
B 500
;
run;

proc report data=have nowd;
  columns dept amt;
  define dept / group 'Department';
  define amt / analysis sum 'Total';
run;

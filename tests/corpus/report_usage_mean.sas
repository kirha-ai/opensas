data have;
  input dept $ amt;
  datalines;
A 100
A 300
B 500
B 700
;
run;

proc report data=have nowd;
  columns dept amt;
  define dept / group 'Dept';
  define amt / analysis mean 'Average';
run;

data have;
  input name $ sales;
  datalines;
Alice 100
Bob 200
;
run;

proc report data=have nowd;
  columns name sales;
run;

/* FEAT-procreport-1: COLUMN reorders vs dataset order; DEFINE label, WIDTH= and
   FORMAT= are honored; ORDER sorts the rows and blanks repeated values. */
data wide;
  input id name $ amt;
  datalines;
2 Bob 200
1 Alice 100
1 Alice 150
;
run;

proc report data=wide nowd;
  columns name amt id;
  define name / order 'Name';
  define amt / format=8.2 width=10 'Amount';
  define id / display 'ID';
run;

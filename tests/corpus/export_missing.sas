data d;
  length s $4;
  input s $ n;
  datalines;
x 5
y .
;
run;
proc export data=d outfile="tests/corpus/includes/em_fixture.csv" dbms=csv replace; run;
proc import datafile="tests/corpus/includes/em_fixture.csv" out=back dbms=csv replace; run;
proc print data=back noobs; run;

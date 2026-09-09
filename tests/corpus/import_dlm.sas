proc import out=t datafile="tests/corpus/includes/import_semicolon.csv" dbms=dlm replace;
  delimiter=";";
  getnames=yes;
  datarow=2;
  guessingrows=5000;
run;
proc print data=t noobs; run;

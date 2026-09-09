proc import out=d datafile="tests/corpus/includes/import_sample.xlsx" dbms=xlsx replace;
  sheet="Data";
run;
proc print data=d noobs; run;

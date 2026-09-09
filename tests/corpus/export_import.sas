data ei_class;
  length name $8;
  input name $ age;
  datalines;
Alice 30
Bob 25
Carol 41
;
run;
proc export data=ei_class outfile="tests/corpus/includes/ei_roundtrip.csv" dbms=csv replace; run;
proc import datafile="tests/corpus/includes/ei_roundtrip.csv" out=ei_back dbms=csv replace; run;
proc print data=ei_back noobs; run;

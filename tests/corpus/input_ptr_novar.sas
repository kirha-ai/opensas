/* BUG-inputptrvar: @n/#n pointer controls in INPUT must NOT create phantom
   blank-named output columns. Only real variables (name, age, city) appear. */
data people;
  input @1 name $5. @7 age 2.;
  datalines;
Alice 30
Bob   25
;
run;

proc print data=people;
run;

proc contents data=people;
run;

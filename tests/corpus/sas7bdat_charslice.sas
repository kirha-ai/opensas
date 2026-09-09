libname s "tests/programs/sas7bdat_read/inputs/te.sas7bdat";
data w;
  set s.te;
run;
proc print data=w noobs; run;

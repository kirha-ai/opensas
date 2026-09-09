libname s "inputs/te.sas7bdat";
libname target "output";

data target.te;
  set s.te;
run;

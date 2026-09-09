libname src "inputs";
libname target "output";

proc sort data=src.nums out=target.sorted;
  by id;
run;

libname src "somedir" access=readonly;
libname out "otherdir";
data _null_;
  put "libname options accepted";
run;

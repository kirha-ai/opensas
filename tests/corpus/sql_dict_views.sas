data W;
  X = 1;
  Y = "a";
  Z = "b";
  output;
run;
proc sql noprint;
  select name into :charvars separated by ' '
  from dictionary.columns
  where libname="WORK" and memname="W" and type="char";
quit;
data _null_;
  put "charvars=&charvars";
run;
data _null_;
  set sashelp.vcolumn(where=(libname="WORK" and memname="W"));
  put "col=" name "type=" type;
run;

/* BUG-xptcreat-novtable: sashelp.vtable — the dictionary view of the current
   library's members (LIBNAME/MEMNAME/MEMTYPE/NOBS/NVAR, upper-cased). Drives
   %XPT_CREAT's `set Sashelp.Vtable; where libname="TARGET";` member enumeration.
   Here: create a few WORK datasets, then list them from the view. */
data alpha; x=1; output; x=2; output; run;
data beta; p=1; q=2; r=3; run;
data _null_;
  set sashelp.vtable end=last;
  where libname="WORK";
  n + 1;
  put "mem=" memname " type=" memtype " nobs=" nobs " nvar=" nvar " last=" last;
  if last then put "count=" n;
run;

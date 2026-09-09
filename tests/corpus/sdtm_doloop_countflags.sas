/* Count how many flag columns are 'Y' with an iterative array scan */
data ae; input USUBJID $ f1 $ f2 $ f3 $ f4 $; datalines;
01-001 Y N Y Y
01-002 N N N Y
01-003 Y Y Y Y
;
run;
data counts;
  set ae;
  array f{4} $ f1-f4;
  nyes = 0;
  do i = 1 to dim(f);
    if f{i} = "Y" then nyes = nyes + 1;
  end;
  keep USUBJID nyes;
run;
proc print data=counts; run;

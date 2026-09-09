/* Recode Y/N flag columns to 0/1 and total them (char + numeric arrays) */
data ae;
  input USUBJID $ f1 $ f2 $ f3 $;
  datalines;
01-001 Y N Y
01-002 N N Y
01-003 Y Y Y
;
run;
data rec;
  set ae;
  array fc{3} $ f1-f3;
  array fn{3} n1-n3;
  do i = 1 to 3;
    fn{i} = (fc{i} = "Y");
  end;
  nflags = sum(of n1-n3);
  keep USUBJID nflags;
run;
proc print data=rec; run;

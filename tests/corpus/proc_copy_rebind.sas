/* GAP-proccopy(b): an EXECUTED libname statement re-binds the libref for the
   steps AFTER it — a real XPT-export %do loop points xptfile at a NEW
   .xpt per iteration. First-declaration-wins wrote every member through one
   path; two members must land in TWO distinct files. */
data one; x = 1; run;
data two; x = 2; run;
%let memname1 = one;
%let memname2 = two;
%macro exportall;
  %do i = 1 %to 2;
    libname xptfile XPORT "tests/corpus/includes/pc_&&memname&i...xpt";
    proc copy in = work out = xptfile;
      select &&memname&i.. ;
    run;
  %end;
%mend;
%exportall;
libname r1 xport "tests/corpus/includes/pc_one.xpt";
libname r2 xport "tests/corpus/includes/pc_two.xpt";
data _null_; set r1.one; put "one " x=; run;
data _null_; set r2.two; put "two " x=; run;

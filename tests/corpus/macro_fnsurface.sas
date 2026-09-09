/* Macro-language function surface: %nrstr & survives re-resolution,
   %symglobl/%symlocal are scope-aware, %qlowcase exists, Q-results mask &.
   BUG-macro-fnsurface. Synthetic. */
%let a = one;
%let b = %nrstr(&a);
data _null_; length s $8;
  s = "&b";  put "NRSTR=[" s "]";
run;
%macro chk;
  %local lv; %let lv=2;
  data _null_;
    g = "%symglobl(lv)"; l = "%symlocal(lv)";
    put "LOCAL G=[" g "] L=[" l "]";
  run;
%mend;
%chk
%let gv = 9;
data _null_;
  g = "%symglobl(gv)"; l = "%symlocal(gv)";
  put "GLOBAL G=[" g "] L=[" l "]";
run;
data _null_; length s $8;
  s = "%qlowcase(ABC)";  put "QLOW=[" s "]";
  s = "%qsubstr(%nrstr(a&b),2,2)"; put "QSUB=[" s "]";
run;

/* Macro-function completeness: %sysevalf types, %qscan, %symexist/%symglobl —
   incl. the defensive "option or default" pattern common in SDTM driver macros.
   Synthetic. macro-macrofns. */
data _null_; length s $12;
  s = "%sysevalf(7/2,int)";     put "SE_INT=[" s "]";
  s = "%sysevalf(7/2,ceil)";    put "SE_CEIL=[" s "]";
  s = "%sysevalf(9/4,floor)";   put "SE_FLOOR=[" s "]";
  s = "%sysevalf(3,boolean)";   put "SE_BOOL=[" s "]";
  s = "%qscan(dm-ae-lb,2,-)";   put "QSCAN=[" s "]";
run;
%macro getopt(name, default);
  %if %symexist(&name) %then %do; data _null_; put "OPT &name=SET"; run; %end;
  %else %do; data _null_; put "OPT &name=&default"; run; %end;
%mend;
%let debug = 1;
%getopt(debug, off)
%getopt(verbose, off)

/* %sysfunc format handling: the optional output format after the function call
   (BUG-sysfuncfmt), 2-arg putn/putc/inputn, %qsysfunc, and nested %sysfunc.
   Deterministic. macro-sysfuncfmt. */
data _null_; length s $24;
  s = "%sysfunc(mdy(1,1,2020),date9.)";          put "OPTFMT=[" s "]";
  s = "%sysfunc(putn(21915,date9.))";            put "PUTN=[" s "]";
  s = "%sysfunc(putn(1234.5,dollar10.2))";       put "PUTN_DOLLAR=[" s "]";
  s = "%sysfunc(upcase(abc),$5.)";               put "OPTFMT_CHAR=[" s "]";
  s = "%sysfunc(inputn(12/31/2020,mmddyy10.))";  put "INPUTN=[" s "]";
  s = "%qsysfunc(putn(21915,date9.))";           put "QSYSF=[" s "]";
  s = "%sysfunc(putn(%sysfunc(mdy(1,1,2020)),date9.))"; put "NESTED=[" s "]";
  s = "%sysfunc(intnx(month,%sysfunc(mdy(1,15,2020)),1),date9.)"; put "NESTED_FMT=[" s "]";
run;

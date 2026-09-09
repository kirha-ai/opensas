/* Autocall string macros %LEFT/%TRIM/%CMPRES and Q-forms: leading/trailing
   blank removal and internal-blank collapse. Synthetic. macro-autocall. */
%let b = ONE;
%let q = %qcmpres(a   %nrstr(&b)   c);
data _null_;
  put "[%left(   hi)]";
  put "[%trim(hi   )x]";
  put "[%cmpres(a    b   c)]";
  put "[&q]";
  put "[%qleft(   &b)][%qtrim(&b   )]";
run;

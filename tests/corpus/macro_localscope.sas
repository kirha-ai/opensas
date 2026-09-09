/* %local scoping: locals + macro params do not leak past the macro; %local shadows
   an outer var and restores it; %global persists. macro-localscope. */
%let dom = STUDYWIDE;
%macro proc(dom);
  %local tmp; %let tmp = working;
  data _null_; put "IN dom=[&dom] tmp=[&tmp]"; run;
%mend;
%proc(AE)
data _null_; put "OUT dom=[&dom] tmp=[&tmp]"; run;
%macro setg; %global keepme; %let keepme = survives; %mend;
%setg
data _null_; put "GLOBAL=[&keepme]"; run;

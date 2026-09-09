/* %sysmacexist (is a macro defined) and %unquote (resolve a masked &/%).
   Synthetic. macro-unquote-macexist. */
%macro rpt; body %mend;
%let x = 5;
%let expr = %nrstr(&x plus one);
data _null_; length s $16;
  s = "%sysmacexist(rpt)";   put "MACEXIST=[" s "]";
  s = "%sysmacexist(nosuch)"; put "MACEXIST_NO=[" s "]";
  s = "%unquote(&expr)";      put "UNQUOTE=[" s "]";
run;

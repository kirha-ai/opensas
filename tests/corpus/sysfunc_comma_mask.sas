/* BUG-sysfunccommamask: a %str(,)-quoted comma must reach the function as a
 * literal argument character, not split the %sysfunc argument list —
 * %sysfunc(catx(%str(,),a,b,c)) is the join-with-comma idiom (SAS: a,b,c).
 * Unquoted commas still split args normally (%sysfunc(sum(1,2,3)) → 6).
 * %put lines show it in the log; the DATA step puts it on stdout for the diff.
 * Expected values are the SAS 9.4 results. Synthetic. sysfunc-comma-mask. */
%put %sysfunc(catx(%str(,),a,b,c));
%put %sysfunc(sum(1,2,3));
%let j = %sysfunc(catx(%str(,),a,b,c));
%let n = %sysfunc(sum(1,2,3));
%let w = %sysfunc(countw(a%str(,)b,%str(,)));
data _null_;
  put "j=&j";
  put "n=&n";
  put "w=&w";
run;

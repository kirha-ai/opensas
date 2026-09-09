/* ISS-letquotedsemi: a quoted `;` in a %let value must not terminate the
   statement (and the closing quote must not trip an unterminated-string error).
   &SEP resolves to the two-quote-plus text `";"`, so SCAN sees `;` as delimiter. */
%let SEP=";";
%put SEP=&SEP;
data _null_;
  x = scan("a;b;c", 2, &SEP);
  put x=;
run;

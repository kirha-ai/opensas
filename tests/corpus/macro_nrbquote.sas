/* BUG-macronrbquoteresolve + BUG-macronrquotemissing: %NRBQUOTE/%NRQUOTE are
   execution-time quoting fns — they RESOLVE &refs/%calls first, THEN mask the
   triggers that survive. %NRSTR stays compile-time verbatim. Synthetic.
   BUG-macronrbquoteresolve. */
%let x=9;
data _null_;
  length s $20;
  s="%nrbquote(&x-a)"; put "NRBQUOTE=[" s "]";
  s="%nrquote(&x-a)";  put "NRQUOTE=[" s "]";
  s="%nrstr(&x-a)";    put "NRSTR=[" s "]";
run;

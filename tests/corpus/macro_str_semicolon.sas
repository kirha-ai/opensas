/* BUG-strsemicolon: %str/%nrstr mask a ; so it does not terminate a %let value,
   a %then/%else branch, or leak in open code. Synthetic. BUG-strsemicolon. */
%let a = %str(x=1; y=2);
data _null_; length s $20; s="&a"; put "LET=[" s "]"; run;
%macro c(n);
  %if &n > 0 %then %str(pos; ok);
  %else %str(neg; bad);
%mend;
data _null_; length s $20; s="%c(5)";  put "THEN=[" s "]"; run;
data _null_; length s $20; s="%c(-1)"; put "ELSE=[" s "]"; run;
%let b = %nrstr(keep=&x; drop=&y);
data _null_; length s $30; s="&b"; put "NRSTR=[" s "]"; run;
%put %str(log; message);

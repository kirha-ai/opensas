/* %eval integer arithmetic resolves to text everywhere it appears — %let RHS, a
   DATA-step expression, and inside an %if guard — instead of leaking `%eval(...)`
   to the lexer. Feature confirm for MEVAL. */
%let n = %eval(2 + 3);
%let m = %eval(10 - 4 * 2);
%let p = %eval((1 + 2) * 3);
%macro parity(k);
  %if %eval(&k / 2 * 2) = &k %then %let r = even;
  %else %let r = odd;
  data _null_; put "&k is &r"; run;
%mend;
data _null_;
  x = %eval(6 + 1);
  put "n=&n m=&m p=&p x=" x;
run;
%parity(4)
%parity(7)

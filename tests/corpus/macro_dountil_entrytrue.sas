/* %DO %UNTIL is post-check: the condition is already true at entry yet the body
   still runs exactly once. %DO %WHILE is pre-check: an at-entry-false condition
   runs zero times. Guards the loop-boundary semantics. macro-doloop. */
%macro until_once;
  %local k n;
  %let k = 5;
  %let n = 0;
  %do %until(&k >= 3);      /* true at entry — must still run once */
    %let n = %eval(&n + 1);
    %let k = %eval(&k + 1);
  %end;
  %global u_iters u_k;
  %let u_iters = &n;
  %let u_k = &k;
%mend;
%until_once

%macro while_none;
  %local w;
  %let w = 0;
  %do %while(1 = 0);        /* false at entry — must run zero times */
    %let w = %eval(&w + 1);
  %end;
  %global w_iters;
  %let w_iters = &w;
%mend;
%while_none

data _null_;
  put "until_iters=&u_iters until_k=&u_k while_iters=&w_iters";
run;

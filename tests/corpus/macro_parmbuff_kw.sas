/* BUG-parmbuffkeyword (tick284 F6): /PARMBUFF with NO parameter list puts the
   whole invocation text in &SYSPBUFF — a keyword-looking arg (a=3) is legal
   text, never "The keyword parameter A was not defined", and the exit code
   stays 0. Synthetic. */
%macro pb / parmbuff;
data _null_;
  put "PBUFF=[&syspbuff]";
run;
%mend;
%pb(1,2,a=3)
data _null_;
  put "AFTER";
run;

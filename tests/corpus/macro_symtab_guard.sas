/* F10 (doc-finder tick284) symbol-table diagnostics: the VALID side stays green
   while four new fail-louds guard the invalid side (captured-diagnostics unit
   tests in macro.zig: %symdel of an automatic, %global of a local, invalid or
   >32-char %let names, multi-char MINDELIMITER=). Pinned here: %symdel of a
   USER var deletes; automatics stay readable; %global-first-then-%let is the
   legal result-var idiom; a single-char MINDELIMITER= gates `in`; a 32-char
   %let name is the legal maximum. Synthetic. */
%let tmp=1;
%symdel tmp;
%macro m;
  %global result;
  %let result=set;
%mend;
%m
%macro memc / minoperator mindelimiter=',';
  %global hit;
  %if b in a,b,c %then %let hit=yes; %else %let hit=no;
%mend;
%memc
%let a2345678901234567890123456789012 = max32;
%if %length(&sysdate9)=9 %then %let autook=yes; %else %let autook=no;
data _null_;
  put "SYMEXIST=%symexist(tmp)";
  put "RESULT=&result";
  put "HIT=&hit";
  put "MAX=&a2345678901234567890123456789012";
  put "AUTOMATIC READABLE=&autook";
run;

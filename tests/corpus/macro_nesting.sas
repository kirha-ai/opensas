/* Nested macro calls, recursion, and enclosing-scope %let resolution.
   Locks already-correct SAS 9.4 macro behavior (doc-finder tick207):
   - %fact recurses correctly (4! = 24);
   - an inner macro's %let updates the ENCLOSING macro's local var
     (SAS scope search runs local->outer->global, updating where found),
     surfaced here via a %global result var;
   - mixed positional + keyword-with-default binding.
   Synthetic. macro-nesting. */
%macro fact(n);%if &n<=1 %then 1;%else %eval(&n*%fact(%eval(&n-1)));%mend;
%macro inner;%let v=fromInner;%mend;
%macro outer;%global outv;%local v;%let v=fromOuter;%inner;%let outv=&v;%mend;
%macro pair(a,b=9);&a-&b%mend;
%outer
data _null_;
  f = %fact(4);
  put "FACT4=" f;
  put "SCOPE=&outv";
  put "PAIR1=%pair(1)";
  put "PAIR2=%pair(1,b=2)";
run;

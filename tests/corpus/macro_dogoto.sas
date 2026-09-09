/* BUG-dogotoindex (tick284 F7): %GOTO out of an iterative %DO leaves the index
   at the value it held at the jump — the standard search-then-report idiom.
   Was: FOUND AT 6 (terminal value). Synthetic. */
%macro find(target);
  %do i = 1 %to 5;
    %if &i = &target %then %goto found;
  %end;
data _null_;
  put "NOT FOUND";
run;
  %return;
  %found:
data _null_;
  put "FOUND AT &i";
run;
%mend;
%find(3)

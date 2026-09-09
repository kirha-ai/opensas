/* Size a %do loop by %sysfunc(countw(list)) then %scan each token — the robust
   count-then-index list walk. corpus-macroedge. */
%let vars = AGE SEX RACE;
%macro walk;
  %let n = %sysfunc(countw(&vars));
  %do i = 1 %to &n;
    data _null_; put "&i/&n=%scan(&vars, &i)"; run;
  %end;
%mend;
%walk

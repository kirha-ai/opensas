/* Normalize a macro value with %upcase before an equality %if — the case-insensitive
   flag-check idiom. corpus-macroedge. */
%macro flag(v);
  data _null_;
  %if %upcase(&v) = YES %then %do; put "&v -> ON"; %end;
  %else %do; put "&v -> off"; %end;
  run;
%mend;
%flag(yes)
%flag(Yes)
%flag(no)

/* BUG-macrodounresolved: a %do bound referencing an unset macro var must error
   loud ("apparent symbolic reference not resolved"), not run one silent
   iteration. The resolved-bound loop runs first and emits 3 rows; the unresolved
   loop then errors to the log and its body never runs — so no stray y=1 row.
   The error is MACRO-scoped (BUG-macrodoscoped): the later step still runs, and
   b holds 1 obs / 0 vars, so y prints missing — same as real SAS.
   (Surfaced by BUG-obsidtmp5, an EPOCH macro's MAXID-unset path.)
   expect-rc: 1 */
%macro good;
  data g;
    %do i=1 %to 3;
      x=&i.; output;
    %end;
  run;
%mend good;
%good
data _null_;
  set g;
  put "GOOD x=" x;
run;

%macro bad;
  data b;
    %do i=1 %to &MAXID.;
      y=&i.; output;
    %end;
  run;
%mend bad;
%bad
data _null_; set b; put "BAD y=" y; run;

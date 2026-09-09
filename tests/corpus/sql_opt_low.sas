/* GAP-sqloptlow-tick271: NOPRINT / NUMBER / FEEDBACK were parsed but ignored
   (tick271 F5–F7). NOPRINT suppresses the query listing while the query still
   runs (INTO still binds macro vars), NUMBER prepends a 1-based "Row" column,
   FEEDBACK echoes the star-expanded statement to the log. */
data d;
  do i = 1 to 3; x = i * 10; output; end;
run;

/* F5 NOPRINT — no listing from either select; &m proves the rows were still
   computed and INTO still bound the macro var. */
proc sql noprint;
  select max(x) into :m from d;
  select i, x from d;
quit;
%put m=&m;
/* …and the stdout-visible proof (the corpus diffs stdout; %put is log/stderr). */
data _null_;
  m = &m;
  put m=;
run;

/* RESET NOPRINT / PRINT mid-step: the first select lists nothing, the second
   lists again. */
proc sql;
  reset noprint;
  select i from d;
  reset print;
  select i from d;
quit;

/* F6 NUMBER — the listing carries a leading Row column. */
proc sql number;
  select i, x from d;
quit;

/* F7 FEEDBACK — the star-expanded statement is echoed before the listing. */
proc sql feedback;
  select * from d;
quit;

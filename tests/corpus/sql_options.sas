/* BUG-sqloptions-tick271: the PROC SQL statement/RESET option header was skipped
   wholesale, so NOEXEC / OUTOBS= / INOBS= were ignored and an unknown option was
   silently swallowed. This pins all four: OUTOBS caps output rows, INOBS caps
   rows read, NOEXEC validates-without-executing (RESET EXEC re-enables), and an
   unrecognized option fails loud.
   expect-rc: 1 */
data d;
  do i = 1 to 5; x = i * 10; output; end;
run;

/* F2 OUTOBS= — a 5-row select prints only the first 2 rows. */
proc sql outobs=2;
  select i, x from d;
quit;

/* F3 INOBS= — only the first 2 source rows are read, so count(*) = 2. */
proc sql inobs=2;
  select count(*) as n from d;
quit;

/* F1 NOEXEC — CREATE is syntax-checked but NOT executed (table stays absent) and
   the SELECT is validated but prints nothing; RESET EXEC re-enables execution, so
   `made` IS created. */
proc sql noexec;
  create table gone as select * from d;
  select i from d;
  reset exec;
  create table made as select i from d where i <= 3;
quit;

data checks;
  gone_exists = exist("gone");
  made_exists = exist("made");
run;
proc print data=checks; run;

/* F4 — an unrecognized option fails loud (ERROR to stderr, the run aborts). The
   select below must therefore never print; if the option were silently accepted
   (the bug) its rows would appear and this fixture's stdout would diverge. */
proc sql zzzbogus=42;
  select i from d;
quit;

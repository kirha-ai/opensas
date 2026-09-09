/* BUG-pointnobsbase (QA tick290 F3): NOBS= and POINT= must share ONE row base
   within a step. Chosen base: PHYSICAL — NOBS= is the descriptor-level count
   (BUG-pointnobs, pinned by set_nobs_window: FIRSTOBS=/OBS=/WHERE window the
   READ, not the descriptor) and POINT= is documented absolute direct access,
   so a direct-access read uses the absolute observation number and the
   obs=/firstobs= window (and global `options obs=`) does not apply to it.
   Before the fix the two disagreed INSIDE ONE STATEMENT — NOBS= reported
   5 while the POINT= range check errored "d has 2 observations" — and the
   out-of-range ERROR turned the contradiction into an errhalt-amplified
   run-killer: `options obs=N;` at the top of a program (the standard debug
   idiom) killed every POINT= loop below it. */
/* BUG-pointwheredsopt: this fixture originally pinned `set d(where=(v>3))
   point=i nobs=n;` reading the PHYSICAL base (where= silently dropped) —
   a semantic encoded BEFORE this repo had the Statements reference. That
   volume forbids the combination outright (SET POINT= Restrictions, printed
   p.335: "You cannot use POINT= with a BY statement, a WHERE statement, or a
   WHERE= data set option."), so the shape is now a loud ERROR (pinned by the
   BUG-pointwheredsopt unit test) and the pin here is retired. What survives:
   NOBS= physical under where= on a SEQUENTIAL read (legal), and POINT=/NOBS=
   physical agreement under obs=/firstobs=/global obs= (obs= is not in the
   restriction). */
data d; input v; datalines;
1
2
3
4
5
;
run;

/* NOBS= reports the physical 5 … (sequential SET + where= — legal) */
data _null_;
  set d(where=(v>3)) nobs=n;
  put 'WHERE NOBS=' n;
  stop;
run;

/* … and the canonical guarded loop reads all 5 physical observations when the
   window is obs= — no contradiction, no error. */
data _null_;
  do i=1 to n;
    set d(obs=2) point=i nobs=n;
    put 'OBS2 i=' i ' v=' v;
  end;
  stop;
run;

/* global `options obs=2;` must not kill a POINT= loop */
options obs=2;
data _null_;
  do i=1 to n;
    set d point=i nobs=n;
    put 'GLOBAL i=' i ' v=' v;
  end;
  stop;
run;
options obs=max;

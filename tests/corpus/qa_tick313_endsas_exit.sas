/* QA tick312 F4 / BUG-endsasexit — POSITIVE CONTROL: ENDSAS is an ordinary
   step boundary that terminates the session NORMALLY (Language Reference: Concepts p.10 "the ENDSAS
   statement is encountered", p.487 "an ENDSAS statement" step boundary), and
   `endsas;` as the last line of a batch program is a production idiom. The
   steps BEFORE it must run and print at exit 0 (pre-fix the run below exited
   1 with "statement ENDSAS is not supported" even though every step was
   correct); the steps AFTER it are never read — that is real ENDSAS
   semantics, so the second table must NOT appear. */
data d; x=1; run;
proc print data=d noobs; run;
endsas;
data e; y=2; run;
proc print data=e noobs; run;

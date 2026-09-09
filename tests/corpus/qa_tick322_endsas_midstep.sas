/* QA tick322 F5 / BUG-endsasmidstep — ENDSAS is an ordinary step boundary
   that terminates the session NORMALLY (Language Reference: Concepts p.10/p.487), mid-step included:
   the step runs with the statements before it (the first listing prints),
   nothing after ENDSAS is even read, exit 0. Pre-fix the PROC loop's fail-loud
   ate it: the listing was LOST and the two post-endsas steps RAN (rc 2).
   Sibling of BUG-endsasexit (top-level endsas, tick322). */
data d; x=1; run;

proc print data=d noobs;
endsas;
run;

/* never reached: ENDSAS ended the session */
data e; y=2; run;
proc print data=e noobs; run;

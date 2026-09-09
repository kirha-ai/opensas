/* BUG-wheredsoptswallow: a MISSPELLED or unsupported parenthesized dataset
   option used to be silently DROPPED at all four dataset-option sites —
   `set d(wehre=(x>2))` ran UNFILTERED (a superset of the intended rows) at
   exit 0. SAS 9.4: ERROR 22-322 and the step does not run. The first four
   steps are the positive control: the supported set (where=/keep=/drop=/
   rename=/firstobs=/obs=/in=) must stay accepted at all four sites (SET,
   PROC data=, DATA output, SQL FROM). The last step's `wehre=` typo must
   fail LOUD (captured diagnostics, exit 1) and print nothing — it runs LAST
   because a step ERROR puts the run in syntax-check mode (BUG-errhalt). If
   the swallow regresses, the last proc prints all five rows and mismatches.
   The typo ERROR says "Unrecognized dataset option wehre=" — rc-1 user-error
   wording, never the rc-2 "not supported" a downstream agent routes on
   (NOTE-typoarmgapwording, D-009).
   expect-rc: 1 */
data d; input x y; datalines;
1 10
2 20
3 30
4 40
5 50
;
run;
/* site 1 — SET input: where= + firstobs=/obs= + in= */
data o; set d(where=(x>1) firstobs=1 obs=4 in=a); if a; run;
proc print data=o noobs; run;
/* site 2 — PROC data= input: keep=/drop= */
proc print data=d(keep=x drop=y) noobs; run;
/* site 3 — DATA output: rename= (with a firstobs= input alongside) */
data p(rename=(x=z)); set d(firstobs=5); run;
proc print data=p noobs; run;
/* site 4 — SQL FROM input: where= */
proc sql; select x from d(where=(x=3)); quit;
/* negative: `wehre` typo ERRORs, the step aborts, and syntax-check mode
   (BUG-errhalt) makes this proc print nothing */
data bad; set d(wehre=(x>2)); run;
proc print data=bad noobs; run;

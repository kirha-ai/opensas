/* BUG-optionsstmtswallow (doc-finder tick300 F3): the OPTIONS statement
   recognized twelve names and silently DISCARDED every other token — a typo
   (`obbs=2` for `obs=2`) silently read EVERY row, and `obs=2k` silently became
   obs=2 because the `k` lexes as a separate token. Now every OPTIONS token is
   either HONOURED below, on the explicit inert allowlist (D-014: display/log/
   session cosmetics a batch interpreter cannot observe), or a LOUD error
   naming it. The loud paths are pinned by in-file tests in main.zig; this
   green fixture is the POSITIVE CONTROL plus the honoured-behavior pins. */

/* positive control: a realistic clinical OPTIONS bundle, all inert here */
options nodate nonumber center pageno=1 msglevel=i compress=yes reuse=no
        validvarname=v7 fmtsearch=(work sashelp) mprint symbolgen minoperator
        mindelimiter=',' bufsize=64k sortsize=16m threads stimer source notes
        nolabel replace;

data names;
  input name $;
  datalines;
Banana
apple
Cherry
;
run;

/* HONOURED: the SORTSEQ= system option supplies PROC SORT's default collation
   (Language Reference: Concepts p.533) — apple sorts before Banana under LINGUISTIC */
options sortseq=linguistic;
proc sort data=names; by name; run;
proc print data=names noobs; run;

/* HONOURED: obs=2k is 2048 — the K suffix is a magnitude, not a token to drop
   (before the fix this silently read 2 rows) */
data five; do i=1 to 5; output; end; run;
options obs=2k;
data b; set five; run;
options obs=max;
proc print data=b noobs; run;

/* HONOURED: NOBYLINE drops the BY line atop each group; BYLINE restores it */
data grp; input k x; datalines;
1 10
1 20
2 30
;
run;
options nobyline;
proc print data=grp noobs; by k; run;
options byline;
proc print data=grp noobs; by k; run;

/* HONOURED: DKRICOND=WARN (Language Reference: Concepts p.184) downgrades a DROP= of a nonexistent
   variable on an INPUT dataset from the default fatal ERROR to a WARNING, so
   the step runs and downstream steps are not errhalt-skipped */
options dkricond=warn;
data c; set five(drop=zz); run;
proc print data=c noobs; run;

/* INERT guard-rail defaults: MERGENOBY=NOWARN (Language Reference: Concepts p.574) and
   VARINITCHK=NOTE are exactly opensas's behavior — accepted, not errors */
options mergenoby=nowarn varinitchk=note;
data m1; x=1; run;
data m2; y=2; run;
data both; merge m1 m2; run;
proc print data=both noobs; run;

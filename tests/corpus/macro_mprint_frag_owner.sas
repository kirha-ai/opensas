/* BUG-mprintfragownerwrong — MPRINT owner attribution is log-only, so the OWNER
   itself is pinned by the `test` blocks in src/main.zig (the corpus runner diffs
   stdout; MPRINT/MLOGIC go to the log). What this fixture pins is the other half,
   and the half that can corrupt data: flushing a pending MPRINT fragment at every
   macro-execution boundary must NOT change the expanded program text.

   That is not hypothetical. Before the fix the boundary flush reset the `;`-scanner
   state mid-string-literal, so `put "x %noop y";` logged `put "x` and then
   mis-terminated everything after it. The statement-splitting bookkeeping sits one
   step away from the text that actually executes, so each shape below runs a step
   whose output is only correct if the text survived the boundary untouched:

     - a text-less callee (%noop) interrupting a statement
     - a %let-only silent callee (executes macro language, emits nothing)
     - a callee that DOES emit text mid-statement (the caller's half, then the
       callee's, then the caller's again)
     - a callee two levels deep that is itself text-less
     - a boundary inside a double-quoted literal (the corruption shape)

   MPRINT is ON throughout on purpose: with NOMPRINT the whole pending-fragment
   path is skipped, so the fixture would prove nothing. */
options mprint nonotes;

data src;
    input name $ v;
    datalines;
alpha 1
beta  2
;
run;

%macro noop; %mend;
%macro silent; %let q=1; %mend;
%macro emitsrc; src; %mend;
%macro twodeep; %noop %mend;

/* text-less callee interrupting `set … ;` */
%macro m_noop; data t1; set %noop src; run; %mend;
%m_noop
/* %let-only callee, same shape */
%macro m_let; data t2; set %silent src; run; %mend;
%m_let
/* callee emits the rest of the statement: caller half | callee half | caller */
%macro m_split; data t3; set %emitsrc run; %mend;
%m_split
/* text-less callee nested two deep */
%macro m_deep; data t4; set %twodeep src; run; %mend;
%m_deep
/* boundary inside a double-quoted literal — must stay one intact string */
%macro m_quote;
    data _null_;
        set src;
        put "row %noop " name "=" v;
    run;
%mend;
%m_quote

proc print data=t1 noobs; run;
proc print data=t2 noobs; run;
proc print data=t3 noobs; run;
proc print data=t4 noobs; run;

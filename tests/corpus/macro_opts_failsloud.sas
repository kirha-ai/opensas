/* GAP-macroopts: %MACRO's option list silently accepted and ignored STORE /
   SECURE / DES= / CMD / STMT — and any other unknown word. The list is now a
   real chain (the BUG-optionsstmtswallow OPTIONS-statement model): PARMBUFF /
   MINOPERATOR / MINDELIMITER= stay honoured (macro_parmbuff_kw,
   macro_minoperator_opt), the NO- forms are the accepted defaults, and the
   five catalog/invocation options — plus any unknown word — ERROR at the
   definition, naming the option, and leave the macro UNDEFINED (D-002), so
   the invocation warns "apparent invocation … not resolved" instead of running
   a macro whose options were dropped. ERRORs/WARNINGs are on the log. The run
   exits 2 (GAP-ebnfrcwrongclass: STORE/CMD are documented %MACRO options —
   Macro Reference printed pp.408-411 — so each is an opensas gap, D-009, and
   a gap outranks BOGUSWORD's rc-1 user error). Typo twin (pure rc 1):
   rc_macro_opt_typo.sas. expect-rc: 2 */
/* CONTROL is the positive control; AFTER ERROR proves a macro-scoped ERROR
   does not syntax-check-skip later steps. */
%macro ok / parmbuff;
data _null_; put 'CONTROL OK'; run;
%mend;
%ok()
%macro s / store;
data _null_; put 'STORE RAN — silent accept regressed'; run;
%mend;
%s
%macro c / cmd;
data _null_; put 'CMD RAN — silent accept regressed'; run;
%mend;
%c
%macro u / bogusword;
data _null_; put 'BOGUS RAN — silent accept regressed'; run;
%mend;
%u
data _null_; put 'AFTER ERROR'; run;

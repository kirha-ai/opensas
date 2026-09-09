/* GAP-ebnfrcwrongclass typo control — `%macro m / stroe;` names no documented
   %MACRO option (the statement's full list, Macro Language: Reference printed
   pp.408-411: CMD DES= MINDELIMITER= MINOPERATOR/NOMINOPERATOR PARMBUFF
   SECURE/NOSECURE STMT SOURCE/SRC STORE). A genuine typo is the user's own
   SAS — exit 1, "fix your SAS" (D-009) — not an opensas gap; the catch-all
   must stay rc 1 while its documented siblings went to rc 2 (gap twin:
   macro_opts_failsloud.sas, expect rc 2). The macro stays UNDEFINED (D-002);
   AFTER ERROR proves the macro-scoped ERROR does not syntax-check-skip the
   later step. expect-rc: 1 */
%macro m / stroe;
data _null_; put 'STROE RAN — silent accept regressed'; run;
%mend;
data _null_; put 'AFTER ERROR'; run;

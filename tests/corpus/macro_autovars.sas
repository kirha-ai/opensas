/* GAP-macroautovars: automatic macro variables are seeded and &SYSERR reflects
   step status — the clinical error-check idiom %if &syserr=0 must take the
   correct branch. Date/time values are checked by SHAPE (fixed widths whatever
   the session date is). Synthetic. GAP-macroautovars.

   BUG-macroerrnostop: the %stamps condition below used to end `… and &sysday ne
   and &sysscp ne`. &SYSSCP is `LIN X64` — the embedded BLANK makes two tokens —
   so the condition was unevaluable and this fixture only reported STAMPS=[ok]
   because a %EVAL error used to let the macro carry on. That is precisely the
   failure class of the worked example at Macro Language Reference printed p.162
   (`%if &word = and or &word = but …`), where SAS emits the character-operand
   ERROR followed by "ERROR: The macro will stop executing." — so real SAS prints
   NEITHER ok nor bad here. The non-empty tests are now %LENGTH(...) > 0, matching
   the three %LENGTH conditions already on the line and leaving no character
   operand for %EVAL to choke on. (p.162's general remedy is %BQUOTE/%STR; it does
   not clear this particular shape because the value's blank survives our
   quoting — filed separately rather than assumed.) */
data _null_; x=1; run;
%if &syserr=0 %then %do;
  data _null_; put "SYSERR=[clean]"; run;
%end;
%else %do;
  data _null_; put "SYSERR=[error]"; run;
%end;

data _null_; put "SYSVER=[&sysver]"; run;

%macro stamps;
  %if %length(&sysdate9)=9 and %length(&sysdate)=7 and %length(&systime)=5 and %length(&sysday) > 0 and %length(&sysscp) > 0 %then %do;
    data _null_; put "STAMPS=[ok]"; run;
  %end;
  %else %do;
    data _null_; put "STAMPS=[bad]"; run;
  %end;
%mend;
%stamps

%macro who;
  data _null_; put "MACNAME=[&sysmacroname]"; run;
%mend;
%who
data _null_; put "OPENNAME=[&sysmacroname]"; run;

%macro cnt;
  data _null_; put "SYSINDEX=[&sysindex]"; run;
%mend;
%cnt

/* F11 (doc-finder tick284) definition diagnostics: the VALID definition surface
   stays green while three new fail-louds guard the invalid side (captured-
   diagnostics unit tests in macro.zig: duplicate parameter names, a %mend name
   that doesn't match the %macro name, an iterative %do in open code). Pinned
   here: distinct positional+keyword params, a matching %mend name, an iterative
   %do inside a macro, and the legal open-code %if/%then/%do; form. Synthetic. */
%macro stats(dsn, label=none);
  %do i = 1 %to 2;
data _null_; put "PASS &i OF &dsn (&label)"; run;
  %end;
%mend stats;
%stats(DM, label=demo)
%let flag=1;
%if &flag %then %do;
data _null_; put "OPEN IF-DO OK"; run;
%end;

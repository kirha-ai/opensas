/* BUG-sortstraysemi (QA tick357 F2 — REGRESSION in d1d38c27): PROC SORT's
   pre-BY statement loop double-advanced on a stray `;` — the new
   stray-punctuation arm consumed it and the pre-existing UNCONDITIONAL trailer
   then ate the NEXT token (the `by`), so the loop failed loud naming the BY
   VARIABLE ('PROC SORT statement x is not supported'), and the step ERROR
   tripped syntax-check mode (BUG-errhalt), killing every later step. A null
   statement is legal SAS, and a semicolon-terminated macro call `%mymacro;` —
   ordinary style inside a PROC step — leaves exactly a bare `;` behind. The
   trailer is now guarded (`if (atTag(…, .semicolon))`), the same form the four
   sibling loops already used: exactly one token per path. This fixture pins
   the whole failure end-to-end: both stray-`;` shapes are ignored, the step
   SORTS (ascending x in the print), and the FOLLOWING step executes at exit 0.
   The loud half — a genuinely unknown sub-statement still errors naming
   itself — is pinned by the captured-diagnostics test in src/proc.zig. */
%macro emptymac; %mend;
data d;
  input x y;
  datalines;
2 20
1 10
3 5
;
run;
proc sort data=d out=s;
  ;            /* a null statement: legal SAS, silently ignored */
  %emptymac;   /* expands to nothing, leaving one bare ';'      */
  by x;
run;
proc print data=s noobs; run;

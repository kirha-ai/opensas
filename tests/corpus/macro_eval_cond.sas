/* QL-C contract fixture: pins the %if/%do %while condition semantics that the
   old string-splitting evaluator (evalBool, "Path A") defined and that the
   consolidated %eval parser must preserve — every line here survived the merge
   bit-identically except the g-block, where %eval GAINED string compares.

   Semantics under contract:
   - comparison is numeric when BOTH operands parse as numbers (floats included),
     else lexical (std.mem.order, case-sensitive);
   - bare leaf truthiness: nonzero INTEGER is true, 0 false, EMPTY leaf false —
     a bare NON-numeric leaf (text or float) is the loud %EVAL character-operand
     ERROR since BUG-ifbaretruthy (manager call: %if agrees with %eval; the loud
     half is pinned by in-file tests in macro.zig, not here — green fixtures only);
   - not/^/~, parenthesised groups, and/or (+ | for or);
   - a mnemonic cmp with an empty operand still compares ("" ne "" is false).

   NOTE-macroevalops: the s9 `<>`-means-NE row was REMOVED from this fixture. The
   Macro Language Reference Table 6.3 "Macro Language Operators" (printed p.87-88)
   spells NE as `¬=` / `^=` / `~=` / NE and lists no `<>`; reading it as NE was a
   silent superset, and it is now the same loud unknown-operator %EVAL error that
   `mod`/`foo` raise (loud half pinned in macro.zig, green fixtures only). `<>`
   keeps its OTHER meanings elsewhere: MAX in the DATA step (minmax_operators) and
   NE in WHERE/PROC SQL (where_ne_op, sql_ne_diamond, Language Reference: Concepts p.219 Table 11.3). */

/* -- string compares, all six mnemonics + symbols ------------------------- */
/* %global: post BUG-macrobareletscope a bare %let in a macro is LOCAL (SAS
   9.4) — result vars read at open code must be declared global. */
%macro strcmp;
  %global s1 s2 s3 s4 s5 s6 s7 s8;
  %if abc = abc %then %let s1=EQ; %else %let s1=BUG;
  %if abc = abd %then %let s2=BUG; %else %let s2=NEQ;
  %if abc ne abd %then %let s3=NE; %else %let s3=BUG;
  %if abc lt abd %then %let s4=LT; %else %let s4=BUG;
  %if abd le abd %then %let s5=LE; %else %let s5=BUG;
  %if abd gt abc %then %let s6=GT; %else %let s6=BUG;
  %if abc ge abd %then %let s7=BUG; %else %let s7=GE-FALSE;
  %if ABC = abc %then %let s8=BUG; %else %let s8=CASE-SENSITIVE;
%mend;
%strcmp
data _null_;
  put "s1=&s1 s2=&s2 s3=&s3 s4=&s4 s5=&s5 s6=&s6 s7=&s7 s8=&s8";
run;

/* -- numeric-vs-lexical canary: 2 lt 10 numerically, but "2" gt "10" -------- */
%macro numcmp;
  %global n1 n2 n3 n4;
  %if 2 lt 10 %then %let n1=NUMERIC; %else %let n1=BUG-LEXICAL;
  %if 1.5 lt 2 %then %let n2=FLOAT; %else %let n2=BUG;
  %if -3 lt 2 %then %let n3=SIGNED; %else %let n3=BUG;
  %if 10 >= 10 %then %let n4=GE; %else %let n4=BUG;
%mend;
%numcmp
data _null_;
  put "n1=&n1 n2=&n2 n3=&n3 n4=&n4";
run;

/* -- bare-leaf truthiness + not/parens + or-bar --------------------------- */
%macro leaf;
  %global t1 t2 t5 t6 t7 t8;
  %if 1 %then %let t1=ONE; %else %let t1=BUG;
  %if 0 %then %let t2=BUG; %else %let t2=ZERO;
  %if not(1 = 2) %then %let t5=NOTPAREN; %else %let t5=BUG;
  %if (1 = 1 or 2 = 1) and 3 = 3 %then %let t6=GROUP; %else %let t6=BUG;
  %if 0 | 1 %then %let t7=ORBAR; %else %let t7=BUG;
  /* empty leaf (empty var — the `%if &flag` guard idiom) is silently FALSE */
  %let e=;
  %if &e %then %let t8=BUG; %else %let t8=EMPTY-FALSE;
%mend;
%leaf
data _null_;
  put "t1=&t1 t2=&t2 t5=&t5 t6=&t6 t7=&t7 t8=&t8";
run;

/* -- empty operand: %let e=; then `&e ne ` resolves to a bare `ne` --------- */
%let e=;
%macro emptycmp;
  %global m1 m2;
  %if &e ne %then %let m1=BUG; %else %let m1=EMPTY-NE-FALSE;
  %if &e = %then %let m2=EMPTY-EQ; %else %let m2=BUG;
%mend;
%emptycmp
data _null_;
  put "m1=&m1 m2=&m2";
run;

/* -- %eval arithmetic under contract (unchanged by the merge) -------------- */
data _null_;
  put "e1=%eval(1 + 2 * 3)";
  put "e2=%eval(10 / 3)";
  put "e3=%eval((1 + 2) * 3)";
  put "e4=%eval(2 lt 10)";
  put "e5=%eval(not 0)";
  put "e6=%eval(1 and 2)";
  put "e7=%eval(0 or 3 gt 2)";
  put "e8=%eval(-7 + 2)";
run;

/* -- %eval string compares: real lexical compares since the QL-C merge (the
   pre-merge parser DROPPED operand words, degrading both sides to 0 — g2 was
   trivially 1 and g3 was 0). */
data _null_;
  put "g1=%eval(abc = abc)";
  put "g2=%eval(abc = abd)";
  put "g3=%eval(abc lt abd)";
run;

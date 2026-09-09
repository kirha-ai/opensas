/* GAP-meanspctlkeywords, cheap half: PRT is a documented ALIAS of PROBT in the
   MEANS family and was decoded by nothing, so `proc means prt` hit the
   warn-and-ignore arm and dropped the column. The hypothesis-testing keyword line
   reads "PROBT | PRT   T" on all three printed pages — Base SAS 9.4 Procedures
   Guide p.1492 (PROC MEANS statement), p.2178 (REPORT) and p.2556 (TABULATE).

   ARM 1 requests probt AND prt in one MEANS step. They must produce IDENTICAL
   columns, because they are two spellings of one statistic — that equality is the
   whole content of "alias", and a regression that mapped prt to t or to a fresh
   statistic would break it. Both label as "Pr > |t|", as PROBT already did.

   ARM 2 is MEANS `OUTPUT OUT=`, where the old failure was worse than a dropped
   column: it errored with "OUTPUT statistic-keyword pr is not recognized", naming
   the USER'S variable name rather than the keyword, because the OUTPUT parser lost
   sync once prt failed to decode. That is the second instance of that misleading
   message found in two ticks (SUMWGT was the first), so it is structural.

   ARM 3 is the surface boundary, and it is the reason this is not a one-line
   change. UNIVARIATE's OUTPUT keyword table (Statistical Procedures Table 4.14,
   printed p.354) lists PROBT with NO PRT alias, and that table DOES spell aliases
   out elsewhere ("KURTOSIS | KURT", "Q1 | P25"), so the omission is meaningful.
   statFromKw is shared by MEANS/MEANS-OUTPUT/TABULATE/REPORT/UNIVARIATE-OUTPUT, so
   without a guard the alias would leak and we would silently honour syntax SAS
   rejects. probt= must keep working there; prt= must keep failing loud. The guard
   matches on the SPELLING because prt decodes to .probt — after decoding, the alias
   is invisible and only the text can tell the two apart. */
data a; input x @@; datalines;
2 4 4 6 8
;
run;
proc means data=a n mean t probt prt;
  var x;
run;
proc means data=a noprint;
  var x;
  output out=o t=t probt=pb prt=pr;
run;
proc print data=o; run;
proc univariate data=a noprint;
  var x;
  output out=ok probt=pb;
run;
proc print data=ok; run;

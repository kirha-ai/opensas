/* GAP-varcolonprefix-procs: the `x:` name-prefix variable list in
   MEANS/UNIVARIATE/FREQ/TABULATE — the four procs that collect their lists
   in proc.zig and resolve via ds.indexOf (PROC PRINT's site was
   GAP-varcolonprefix; DROP/KEEP GAP-dropcolon; OF GAP-ofcolonprefix).
   Language Reference: Concepts printed p.69 / p.70 Table 4.5 define the name-prefix form; printed
   p.62 settles the ORDER — a variable list refers to its variables "in the
   same order that SAS uses to keep track of the variables" (PDV order).
   ONE expander (proc.zig expandVarPrefixes, the twin of main.zig's
   expandVarList) serves every list below — never a prefix test at each
   ds.indexOf. A prefix matching nothing is a loud rc 1, matching the OF and
   PRINT empty-match arms (see var_colon_prefix_procs_nomatch.sas). */
data t;
  input x2 x1 x10 y c2 $ c1 $;
  datalines;
1 2 3 10 a b
4 5 6 20 a c
7 8 9 30 b b
;

/* MEANS: PDV-order pin — the columns were CREATED x2, x1, x10, so PDV
   order (x2 x1 x10) and alphabetical (x1 x10 x2) differ, and this is PDV.
   A plain name mixes with the prefix. */
proc means data=t n mean;
  var y x:;
run;

/* MEANS CLASS takes the same wire form (PDV order c2, c1 in the header). */
proc means data=t n mean maxdec=1;
  class c:;
  var x1;
run;

/* UNIVARIATE: an UPPERCASE prefix — the match is case-insensitive; the
   three Variable: sections pin PDV order a second way. */
proc univariate data=t;
  var X:;
run;

/* FREQ: `tables x:` is one-way requests — one table per matched variable,
   PDV order, then the plain-name request. */
proc freq data=t;
  tables x: y;
run;

/* TABULATE: the CLASS list takes the prefix; the TABLE expression names
   EXPANDED vars, matched against the not-yet-expanded wire form at parse
   time (nameOrPrefixListed). */
proc tabulate data=t;
  class c:;
  table c2, x1*sum;
  table c1, x1*sum;
run;

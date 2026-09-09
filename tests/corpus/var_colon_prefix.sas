/* GAP-varcolonprefix: `var x:;` — the name-prefix variable list in PROC
   PRINT's VAR statement (and its ID/SUM siblings, same `variable(s)` doc
   shape). Procedures guide printed pp.1784-1785 (PRINT's own VAR entry):
   `VAR variable(s)`, no restriction on list form; Language Reference: Concepts printed p.69
   Example 7 puts a variable list in PROC PRINT's own VAR statement, the
   prefix form defined beside it, and p.62 settles the ORDER: a variable
   list refers "in the same order that SAS uses to keep track of the
   variables" — PDV order, matching DROP/KEEP (GAP-dropcolon) and OF
   (GAP-ofcolonprefix). collectNames keeps `x:` as one "x:" entry (the
   parseNameList model); expandVarList expands it against the dataset. */
data t;
  input x2 x1 x10 y;
  datalines;
1 2 3 4
5 6 7 8
;

/* PDV order pin: the columns were CREATED x2, x1, x10 — PDV order
   (x2 x1 x10) and alphabetical (x1 x10 x2) differ, and this is PDV. */
proc print data=t;
  var x:;
run;

/* prefix mixed with a plain name, and a SUM prefix — the totals prove the
   expansion happened before printTable's per-name total matching */
proc print data=t;
  var y x:;
  sum x:;
run;

/* case-insensitive prefix; ID pins the third statement sharing collectNames
   (ID columns render leftmost and replace Obs) */
proc print data=t;
  id X:;
  var y;
run;

/* control: an ordinary `var x y;` list is unchanged */
proc print data=t;
  var x2 y;
run;

/* control: the DROP/KEEP prefix wildcard (GAP-dropcolon) is unchanged */
data k;
  set t;
  keep x:;
run;
proc print data=k;
run;

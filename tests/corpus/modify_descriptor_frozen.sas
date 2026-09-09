/* GAP-ch23med-tick296 F3 — a MODIFY master's DESCRIPTOR IS FROZEN.

   MODIFY updates in place, so the descriptor is not the step's to rewrite.
   DATA Step Statements ref printed p.240 (pdf 251; that page's own footer reads
   "240 Chapter 2 / Dictionary of SAS DATA Step Statements"), the statement's
   Restrictions:
       This statement cannot modify the descriptor portion of a SAS data set,
       such as adding a variable.
   Language Reference: Concepts printed p.585 (running header "Combining SAS Data Sets: Methods 585")
   repeats it as a Note. Language Reference: Concepts printed p.588 Table 23.3, row "Scope of changes",
   gives the FULL extent — and this is why the fix freezes the whole descriptor
   rather than guarding the add:
       cannot change the data set descriptor information, so changes such as
       adding or deleting variables, variable labels, and so on, are not valid

   NOT AN ERROR — doc-settled, not chosen. Statements ref printed p.253 (footer
   "MODIFY Statement 253"), the Example 3 discussion:
       MODIFY does not add NWSTOCK to the INVTY.STOCK data set because that
       would modify the data set descriptor. Thus, it is not necessary to put
       NWSTOCK in a DROP statement.
   So an out-of-descriptor variable is simply not written, with no diagnostic,
   and the reference states outright that a DROP is unnecessary. Failing loud
   would have rejected the reference's OWN Example 3, whose NWSTOCK is
   deliberately left undropped (D-014). Language Reference: Concepts states the rule in validity
   language only and defers the mechanism to this very volume ("For complete
   information, see MODIFY Statement in the SAS DATA Step Statements:
   Reference", printed p.586), so the two volumes compose rather than conflict.

   WHAT WENT WRONG: opensas rebuilt the output schema from the PDV on every
   commit, so all three descriptor edits leaked into the master at exit 0. The
   FILED symptom (C1) is the mildest of them; C3 was destroying data.

   REVERTING THE FIX GAINS WRONG VALUES, not just a missing message: C1 grows a
   phantom column, C3 LOSES column y and every value in it, C4 renames x to xx.
   expect-rc: 0 */

/* ---- C1 (the filed symptom): a new variable is NOT added ---- */
data d1; input id x; datalines;
1 10
2 20
;
run;
data d1;
  modify d1;
  brandnew = 99;      /* usable in the step, never written to the descriptor */
  x = x + brandnew;   /* …and its VALUE is genuinely used */
run;
proc print data=d1 noobs; title "C1 new var absent, its value still applied"; run;
proc contents data=d1; run;

/* ---- C2: the reference's own Example 3 shape — a TRANSACTION variable
        (NWSTOCK) is not added, and needs no DROP statement ---- */
data stock; input partno $ instock; datalines;
K89R 34
M4J7 98
;
run;
data addinv; input partno $ nwstock; datalines;
K89R 55
M4J7 21
;
run;
data stock;
  modify stock addinv;
  by partno;
  instock = instock + nwstock;
run;
proc print data=stock noobs; title "C2 p.253 Example 3: summed, nwstock absent"; run;

/* ---- C3: DELETING a variable is forbidden too — Table 23.3 says "adding or
        deleting". This is the worst of the three: opensas used to DROP the
        column from the master and destroy every value in it. ---- */
data d3; input id x y; datalines;
1 10 100
2 20 200
;
run;
data d3;
  modify d3;
  x = x + 1;
  drop y;             /* cannot delete from a frozen descriptor */
run;
proc print data=d3 noobs; title "C3 drop ignored: y and its values survive"; run;

/* ---- C4: RENAME is a descriptor change as well ---- */
data d4; input id x; datalines;
1 10
;
run;
data d4;
  modify d4;
  rename x = xx;      /* cannot rename in a frozen descriptor */
run;
proc contents data=d4; title "C4 rename ignored: column is still x"; run;

/* ---- C5: the master's own column ATTRIBUTES ride through the freeze ---- */
data fm;
  amt = 1500;
  format amt dollar10.2;
  label amt = 'Amount';
run;
data fm;
  modify fm;
  amt = amt * 2;
run;
proc print data=fm noobs; title "C5 format survives, value updated"; run;
proc contents data=fm; run;

/* ---- C6 (D-014 control): ONLY the master is frozen. Statements ref printed
        p.260 Example 8 is `data invty.stock invty.stock95 invty.stock97;
        modify invty.stock;` — the non-master outputs are BRAND-NEW data sets
        and must still take the ordinary full-PDV schema. ---- */
data mst; input id v; datalines;
1 5
2 6
;
run;
data mst side;
  modify mst;
  extra = 42;
  v = v * 10;
run;
proc contents data=mst;  title "C6 master mst FROZEN: no extra"; run;
proc print data=side noobs; title "C6 side is new: full PDV, has extra"; run;
proc contents data=side; run;

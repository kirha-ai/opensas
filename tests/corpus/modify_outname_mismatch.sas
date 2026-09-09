/* BUG-modifyoutnamemismatch — MODIFY's MASTER must also be an output data set
   of the DATA statement.

   DATA Step Statements ref printed p.241 (pdf 252; the page's own footer reads
   "MODIFY Statement 241"), the `master-data-set` argument:
       Restrictions  This data set must also appear in the DATA statement.
   Language Reference: Concepts printed p.588, Table 23.3 "MODIFY with BY versus UPDATE", row "Where to
   specify the modified data set":
       specify the updated data set in both the DATA and the MODIFY statements
   Language Reference: Concepts printed p.250 kills the "it makes a copy" reading outright: "When you
   use a MODIFY statement in a DATA step ... SAS does not create a new copy of
   the data set."

   `data b; modify d;` used to degrade SILENTLY to `data b; set d;` at exit 0:
   the edits landed in a brand-new `b` and `d` — the data set the author asked
   to update IN PLACE — was left byte-identical, with no diagnostic. Real-world
   shape is a typo in the DATA statement (`data mater; modify master;`).

   The controls run FIRST, so they print before the erroring step halts the run:
   whatever this rejects, the LEGAL MODIFY shapes must survive (D-014). Printed
   p.260 Example 8 (`data invty.stock invty.stock95 invty.stock97; modify
   invty.stock;`) makes the rule MEMBERSHIP, not equality, so C4/C5 pin extra
   outputs beside the master, and C5 pins that the TRANSACTION data set is NOT
   itself required to be an output.

   REVERTING THE FIX GAINS WRONG VALUES, it does not merely lose an error: the
   two PROC PRINTs under "the bug" come back, showing `d` still 10/20/30 (the
   update never happened) and `b` holding 1000/2000/3000 (the edits went to the
   wrong data set) at exit 0.

   expect-rc: 1 */

data d;
  input id x;
  datalines;
1 10
2 20
3 30
;
run;

/* ---- controls: the legal MODIFY shapes, all of which must still work ---- */

/* C1 matching name, single data set — plain sequential in-place rewrite */
data d;
  modify d;
  x = x + 1;
run;
proc print data=d noobs; title "C1 matched"; run;

/* C2 the match is case-insensitive, like every other SAS name */
data D;
  modify d;
  x = x + 1;
run;
proc print data=d noobs; title "C2 case-insensitive"; run;

/* C3 `work.d` and `d` are the SAME member — Library.put/find compare through
   the same strip, so the membership test must too or this legal shape dies */
data work.d;
  modify d;
  x = x + 1;
run;
proc print data=d noobs; title "C3 work-qualified"; run;

/* C4 printed p.260 Example 8's shape: extra outputs BESIDE the master */
data d spare;
  modify d;
  x = x + 1;
run;
proc print data=d noobs; title "C4 master + extra output"; run;

/* C5 master is an EXTRA rather than the primary, and the TRANSACTION data set
   is not an output at all — only master-data-set carries the restriction */
data t;
  input id x;
  datalines;
2 777
;
run;
data other d;
  modify d t;
  by id;
run;
proc print data=d noobs; title "C5 master-as-extra, transaction not an output"; run;
proc print data=t noobs; title "C5 transaction untouched"; run;

/* ---- the bug: master is named nowhere in the DATA statement ---- */
/* Both drivers were wrong, not just the single-data-set one the ticket named:
   the transaction-driven `modify d t; by id;` rebuild-commit also re-emits the
   master through the step's output dataset. This is the single-data-set half;
   modify_outname_mismatch_by.sas pins the transaction-driven sibling. */
data b;
  modify d;
  x = x * 100;
run;

/* Never reached once the step errors — and that is the point. Under the bug
   these printed, and what they printed was the wrong answer. */
proc print data=d noobs; title "d MUST NOT be reachable here"; run;
proc print data=b noobs; title "b MUST NOT EXIST"; run;

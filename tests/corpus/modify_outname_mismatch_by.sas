/* BUG-modifyoutnamemismatch, the SIBLING the ticket did not name — MODIFY WITH
   BY had the identical defect and for the identical reason.

   The ticket described `data b; modify d;`, the single-data-set sequential
   driver. But transaction-driven `data b; modify d t; by id;` is a SEPARATE
   driver (buildModify/ModifyState, BUG-modifybymasterdriven) and it was just as
   wrong: its rebuild-commit (modifyFlush) re-emits the master through the same
   `outputAll`, i.e. through the DATA statement's output data set. So the merged
   result landed in `b` and the master `d` — the whole point of an in-place
   update — was left byte-identical, at exit 0, with no diagnostic.

   That shared root is why the guard is ONE check ahead of buildDriver rather
   than one per driver: both drivers commit through the step's output data set,
   so both need the master to BE that data set.

   Language Reference: Concepts printed p.588 Table 23.3 is titled "MODIFY with BY versus UPDATE" and
   is therefore about exactly this form: "specify the updated data set in both
   the DATA and the MODIFY statements".

   Only the MASTER is restricted. `t` is a transaction data set and must NOT
   have to appear in the DATA statement — modify_outname_mismatch.sas C5 pins
   the positive half of that.

   REVERTING THE FIX GAINS A WRONG VALUE: the trailing PROC PRINTs return, `d`
   still reads 10/20/30 with the transaction never applied, and `b` holds the
   merged 10/999/30 that should have gone into `d`.

   expect-rc: 1 */

data d;
  input id x;
  datalines;
1 10
2 20
3 30
;
run;

data t;
  input id x;
  datalines;
2 999
;
run;

data b;
  modify d t;
  by id;
run;

proc print data=d noobs; title "d MUST NOT be reachable here"; run;
proc print data=b noobs; title "b MUST NOT EXIST"; run;

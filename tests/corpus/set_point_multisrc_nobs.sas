/* BUG-pointredefinesnobs — `point=` must not shrink the source list or NOBS=.

   `set a b point=p nobs=n;` bound only `a`: n came back 3 where the IDENTICAL
   list without `point=` gives 5 (GAP-nobsmultisrc, fixture set_nobs_multisrc),
   and obs 4-5 were unreachable. The two halves compound into the real damage —
   see block 4.

   DOC-SETTLED, no oracle needed. SAS 9.4 DATA Step Statements ref printed p.334
   (that page's own footer reads "334 Chapter 2 / Dictionary of SAS DATA Step
   Statements"), the SET statement's NOBS= argument:
       creates and names a temporary variable whose value is usually the total
       number of observations in the input data set or data sets. If more than
       one data set is listed in the SET statement, the value of the NOBS=
       variable equals the total number of observations in the data sets that
       are listed.
   with no POINT= exception, and the same entry says it outright:
       Interaction  The NOBS= and POINT= options are independent of each other.

   That the ADDRESSING spans all the sources — rather than POINT= being
   single-source with NOBS= merely reporting a larger number — is settled on the
   same page by the OPEN=DEFER restriction:
       When you specify the DEFER option, you cannot use the KEY= statement
       option, the POINT= statement option, or the BY statement. These
       constructs imply either random processing or interleaving of
       observations from the data sets, which is not possible unless all data
       sets are open.
   and POINT='s own Restrictions list (printed p.335) bars BY, WHERE, WHERE=,
   KEY=, transport/sequential/view sources and CAS — a multi-dataset list is NOT
   among them, so `set a b point=p;` is legal SAS and must work.

   OBSERVATION-PATH NOTE: every value below is reported with PUT to the log.
   NOBS= is the thing under test, so anything that reads through the SET/NOBS=
   machinery would be measuring itself. Block 6 exits 0 since NOTE-pointoorhard
   (out-of-range POINT= NOTEs and continues; it no longer halts the step).
   expect-rc: 0 */

data a; input x; datalines;
10
20
30
;
run;
data b; input x; datalines;
40
50
;
run;

/* 1 — the internal-consistency pair, side by side on the IDENTICAL list.
   These two numbers were 5 and 3; they must now agree. */
data _null_;
  set a b nobs=n;
  if _n_=1 then put "1 without point n=" n;
run;
data _null_;
  p = 1;
  set a b point=p nobs=n;
  put "1 with    point n=" n;
  stop;
run;

/* 2 — the READ SET: obs 4 and 5 live in `b` and must be reachable. Under the
   bug, p=4 raised "invalid observation number 4: a has 3 observations". */
data _null_;
  do p = 1 to 5;
    set a b point=p;
    put "2 p=" p " x=" x;
  end;
  stop;
run;

/* 3 — the boundary itself: a has 3 rows, so obs 3 is a's last and obs 4 is b's
   first. One address space, no seam. (One SET statement in a loop — two SET
   statements would trip the unrelated "second or nested SET source" gap.) */
data _null_;
  do p = 3 to 4;
    set a b point=p;
    put "3 obs" p "=" x;
  end;
  stop;
run;

/* 4 — THE COMPOUND FAILURE, which is why this was silent. The canonical POINT=
   idiom takes its bound FROM nobs=, so an under-reported n made the loop stop
   at 3 and never reach the out-of-range guard that would have exposed it:
   2 of 5 observations vanished at exit 0 with no diagnostic. */
data _null_;
  do p = 1 to n;
    set a b point=p nobs=n;
    put "4 p=" p " x=" x;
  end;
  stop;
run;

/* 5 — CONTROLS: the single-source spelling is untouched. */
data _null_;
  p = 2;
  set a point=p nobs=n;
  put "5 single n=" n " x=" x;
  stop;
run;

/* 6 — out of range is still LOUD past the CONCATENATED end (6 > 3+2), not at
   the old single-source boundary. NOTE-pointoorhard: it no longer halts —
   _ERROR_=1 + a NOTE, and the step CONTINUES, so the PUT below DOES run and
   shows the never-loaded (missing) x of the failed iteration. */
data _null_;
  p = 6;
  set a b point=p;
  put "6 CONT x=" x;
  stop;
run;

/* BUG-sqlcolwidthloss, set-op half — a UNION's result column takes the WIDEST
   arm's declared char width, not the left arm's.

   SQL Procedure User's Guide, printed p.397-398, Table 8.1 "Resolving Different
   Lengths for the Same Variable": with a data set on both sides, "the length of
   VAR1 in NewTable is the maximum length of VAR1 across both sources".

   This is load-bearing, not cosmetic: a SELECT-clause width TRUNCATES the stored
   value (BUG-sqlselectlength / GAP-sqldatatypewidth — and printed p.268 says
   the values "are either truncated or padded with blanks (if character data) as
   necessary to meet the specified length attribute"). Carrying only the LEFT
   arm's width therefore SILENTLY DESTROYED the right arm's longer values:
   'ABCDEF' out of a `$6` column came back as 'ABC' under a `$3` left arm. Both
   arm orders are pinned below so neither can regress into the other. */

data t1; length b $3; b='ABC';    output; run;
data t2; length b $6; b='ABCDEF'; output; run;

proc sql;
  title 'narrow arm first — the wide value must survive whole';
  select b, lengthc(b) as lb from t1 union all select b, lengthc(b) as lb from t2;
  title 'wide arm first — same result column width, same values';
  select b, lengthc(b) as lb from t2 union all select b, lengthc(b) as lb from t1;
quit;

title;
/* the resolved width rides into a created table, so CONTENTS shows the max */
proc sql;
  create table u_nw as select b from t1 union all select b from t2;
  create table u_wn as select b from t2 union all select b from t1;
  create table u_oc as select * from t1 outer union corr select * from t2;
quit;
proc contents data=u_nw; run;
proc contents data=u_wn; run;
proc contents data=u_oc; run;
proc print data=u_nw; run;
proc print data=u_oc; run;

/* EXCEPT / INTERSECT keep the left arm's rows, and still resolve to the max */
proc sql;
  title 'except';
  select b from t2 except select b from t1;
  title 'intersect';
  select b from t2 intersect select b from t2;
quit;

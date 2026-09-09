/* GAP-sqlsortseqlinguistic — the LOUD arm. `proc sql sortseq=<anything but
   ASCII/LINGUISTIC>` used to be swallowed by isNoopSqlOption and change
   nothing, so a query asking for EBCDIC collation quietly came back in ASCII
   order: silent wrong row order, which D-002 exists to prevent.

   rc 2, not 1, and the arm is KNOWINGLY CONFLATED. SQL Procedure User's Guide
   printed p.261 (`=== pdf 276 ===`) defines the value as
   `SORTSEQ=sort-table | LINGUISTIC`, where sort-table "specifies a translation
   table that YOU CREATED with PROC TRANTAB" — the valid set is user-created
   names, so unlike the SORTSEQ= SYSTEM option (which has the closed list at
   Procedures Guide p.2410) there is NO enumeration here that could split a
   typo from a real table. Same shape as audit §5d's LEFT rows. D-018 then
   decides it: an undecidable value stays on the gap arm, because a wrong rc 2
   costs one spurious "file an opensas issue" while a wrong rc 1 tells a user
   their valid SAS is broken.

   `sortseq=linguistic(<collating-options>)` is the same class and also rc 2 —
   documented valid SAS (Procedures Guide p.2410, `LINGUISTIC<(collating-
   options)>`) that opensas does not implement. It is pinned in sql.zig's
   in-source test rather than here, one error per fixture.

   The rc-1 control is a genuinely unknown option name (`sortseqq`), which
   still lands on PROC SQL's existing "unrecognized option" arm — also pinned
   in-source, so both arms are held.
   expect-rc: 2 */
data t;
  input n $ @@;
datalines;
b a
;
run;
proc sql;
  select n from t order by n;
quit;
proc sql sortseq=ebcdic;
  select n from t order by n;
quit;

/* BUG-sortseqbaresuperset DECLINED — bare `options sortseq=linguistic;` is
   CONFORMANT, and this pins the half an rc pin cannot state: that it is
   actually HONOURED, not merely accepted.

   The ticket read the Procedures Guide's p.2415 Restrictions line ("…is not
   available for the system option SORTSEQ") as making our rc 0 a silent
   superset. That line is refuted four times, twice inside its own chapter:
     * printed p.2403 (`=== pdf 2452 ===`), "Linguistic Sorting of Data Sets and
       ICU": "Starting in the third maintenance release of SAS 9.4, you can
       specify linguistic collation using the SORTSEQ= option in the SQL
       procedure and by specifying the SORTSEQ=LINGUISTIC system option." The
       date is what settles it — the restriction states the pre-M3 behaviour.
     * same page, Note: "Only PROC SORT and PROC SQL are affected when the
       SORTSEQ=LINGUISTIC system option is specified."
     * SQL Procedure User's Guide printed p.261 (`=== pdf 276 ===`): "If
       LINGUISTIC is specified for the SORTSEQ system option, then PROC SQL
       honors the setting. The setting of the PROC SQL SORTSEQ option overrides
       the setting of the SORTSEQ system option."
     * same entry's CAUTION: "Do not use the PROC SQL SORTSEQ=LINGUISTIC option
       or the SORTSEQ=LINGUISTIC system option when a SORTKEY function is used
       in an ORDER BY clause."

   What is pinned: the system option really applies linguistic collation to a
   later PROC SORT with no SORTSEQ= of its own. Case-folded dictionary order
   puts apple before Banana before Zebra; the ASCII default (pinned by the
   second sort, which the option must NOT reach because ASCII resets it) puts
   Banana and Zebra before apple. So a change that made this statement inert
   would show up here even though the rc stayed 0 — an accepted-but-ignored
   system option is the silent-superset failure this ticket suspected, and this
   fixture is what would catch it.

   Twin rc_sortseq_linguistic_sysopt.sas holds the modifier form at rc 2.
   PROC SORT's own SORTSEQ=LINGUISTIC is a different site (proc.zig) and is
   pinned by sort_contents_opts.sas.
   expect-rc: 0 */
options sortseq=linguistic;
data d;
  input n $ @@;
datalines;
Zebra apple Banana
;
run;
proc sort data=d out=ling;
  by n;
run;
proc print data=ling;
  title "linguistic: apple Banana Zebra";
run;
options sortseq=ascii;
proc sort data=d out=asc;
  by n;
run;
proc print data=asc;
  title "ascii: Banana Zebra apple";
run;

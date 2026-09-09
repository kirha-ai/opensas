/* BUG-attribemptyvaluenoop — a DATA-step `attrib a format=;` / `attrib a
   informat=;` parsed, DROPPED the empty value and no-op'd at rc 0 with zero
   diagnostics: the old format stayed attached, which is the silent success
   D-002 forbids.

   The empty spelling is SAS's own sample code — but for PROC DATASETS MODIFY
   (Procedures Guide printed p.691 Example 1, `attrib _all_ format=;`, which
   dd_format_strip.sas / proc_datasets_contents.sas pin and proc.zig honours).
   The Statements Ref rules it out of the DATA step in one sentence at printed
   p.36 — "You can use ATTRIB in a PROC step, but the rules are different" —
   and gives the DATA-step slots at printed p.34 as `FORMAT=format` /
   `INFORMAT=informat`, operand required (contrast `LENGTH=<$>length` on the
   same page: the volume brackets what is optional). So this is invalid SAS,
   a USER error → rc 1 (D-009), not an opensas gap.

   Cases A-C are the POSITIVE CONTROL: everything the doc DOES bless must keep
   working, most of all the documented removal route this ticket must not
   regress. Case D is the loud one and comes LAST, because a step ERROR puts
   the run into syntax-check mode (BUG-errhalt) and skips every later step.
   expect-rc: 1 */

data src;
  x = 21929; format x date9.; informat x date9.;
  output;
run;

/* A — the DOCUMENTED DATA-step removal: a bare FORMAT statement naming the
   variable and no format, placed after the SET (Statements Ref printed p.112,
   worked at printed p.115 Example 3 `format x;`). x must print RAW. */
data a; set src; format x; run;
proc print data=a noobs; run;

/* B — bare INFORMAT is the informat-side twin; it must NOT touch the display
   format, so x still prints 15JAN2020. */
data b; set src; informat x; run;
proc print data=b noobs; run;

/* C — every ATTRIB clause that carries a real value still applies. */
data c; attrib q format=comma10.2 informat=best8. label='Q' length=8; q=1234.5; run;
proc print data=c noobs; run;

/* D — the empty value is now LOUD, and the message names the p.112 route. */
data d; set src; attrib x format=; run;
proc print data=d noobs; run;

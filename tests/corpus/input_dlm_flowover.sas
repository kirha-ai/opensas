/* GAP-inputdlmnoflow — FLOWOVER for the DELIMITED reader, which had none.

   Pins the INFILE FLOWOVER/DSD contrast worked on the SAS 9.4 DATA Step
   Statements reference, printed p.145 (pdf marker 156; that page's OWN footer
   reads "INFILE Statement 145" — both the marker arithmetic and the printed
   number agree, per D-020). The reference shows a comma-delimited three-value
   INPUT over three records where record 2 has an EMPTY middle field and record
   3 an EMPTY first field, and states that with FLOWOVER in effect the data set
   holds TWO observations, not three, the second built incorrectly from the
   tail of record 2 plus the head of record 3.

   Why obs 2 ends with record 3's first value: without DSD, consecutive
   delimiters collapse (the reference's own point — "the INPUT statement cannot
   detect the missing value"), so record 2 yields only two values; FLOWOVER then
   takes record 3 for the third variable and reads its first value. opensas
   produced THREE observations with obs 2 ending in `.` because io.readDelim
   never spilled across records at all — it read missing off the end of the
   record, which is MISSOVER's job (printed p.133), not FLOWOVER's (printed
   p.132).

   Block 2 is the reference's remedy for the same data, on the next page: "To
   correct the problem, use the DSD option in the INFILE statement." Both halves
   of the contrast are pinned here, because getting one right by breaking the
   other is the failure mode — an EMPTY field must stay a missing value and must
   NOT trigger a spill. Exhaustion is the trigger, not emptiness.
   expect-rc: 0 */

/* 1 — the p.145 shape. TWO observations; obs 2 is 69 63 2. */
data heats;
  infile datalines delimiter=',';
  input heat1 heat2 heat3;
  datalines;
64,58,71
69,,63
,2,2
;
run;
proc print data=heats; title "1 p.145: two obs, obs2 = 69 63 2"; run;

/* 2 — the reference's own correction: DSD detects the missing value, so nothing
   is exhausted, nothing spills, and there are THREE observations. */
data dsdfix;
  infile datalines dsd;
  input heat1 heat2 heat3;
  datalines;
64,58,71
69,,63
,2,2
;
run;
proc print data=dsdfix; title "2 p.145 DSD fix: three obs, obs2 = 69 . 63"; run;

/* 3 — CONTROL (D-014): MISSOVER must NOT spill in the delimited path either. It
   is handed a one-record window, so the shared advance cannot fire, and the
   partial observation is KEPT with missing — its documented behaviour. */
data mo;
  infile datalines delimiter=',' missover;
  input a b c;
  datalines;
1,2,3
4,5
;
run;
proc print data=mo noobs; title "3 MISSOVER keeps 4 5 ."; run;

/* 4 — CONTROL: TRUNCOVER, the same on the other short-record option. */
data tc;
  infile datalines delimiter=',' truncover;
  input a b c;
  datalines;
1,2,3
4,5
;
run;
proc print data=tc noobs; title "4 TRUNCOVER keeps 4 5 ."; run;

/* 5 — CONTROL: a fully satisfied delimited read is untouched by any of this. */
data ok;
  infile datalines delimiter=',';
  input a b c;
  datalines;
1,2,3
4,5,6
;
run;
proc print data=ok noobs; title "5 satisfied: two obs, unchanged"; run;

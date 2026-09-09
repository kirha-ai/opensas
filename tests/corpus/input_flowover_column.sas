/* BUG-flowovercolumn + NOTE-flowovernote (Language Reference: Concepts p.171): FLOWOVER — the DEFAULT
   short-record mode — used to flow only for LIST input; COLUMN and FORMATTED
   input silently behaved as TRUNCOVER (a different observation count AND
   different values), and the doc-mandated NOTE "SAS went to a new line when
   INPUT statement reached past the end of a line." was never emitted on ANY
   path. Now all three styles flow to the next record (one observation each) and
   the NOTE fires (stderr, so it is not in this golden).
   ponytail: the post-flow resume column is needs-oracle (doc-finder-tick287 F5)
   — column input re-reads the SAME absolute columns of the new record (3-4 →
   EF), formatted input resumes at column 1 ($2. → CD). Both UNVERIFIED against
   a real SAS; the flow and the NOTE themselves are doc-settled. The SHORT step
   pins the boundary: a field that STARTS inside the record but ends past it
   reads SHORT — no flow (datalines_char_informat pins the same rule). */
data _null_;
  input a $ 1-2 b $ 3-4;
  put 'COLUMN    n=' _n_ ' a=[' a '] b=[' b ']';
datalines;
AB
CDEFGH
;
run;
data _null_;
  input a $2. b $2.;
  put 'FORMATTED n=' _n_ ' a=[' a '] b=[' b ']';
datalines;
AB
CDEFGH
;
run;
data _null_;
  input a $ b $;
  put 'LIST      n=' _n_ ' a=[' a '] b=[' b ']';
datalines;
AB
CDEFGH
;
run;
data _null_;
  input a $ 1-2 b $ 2-4;
  put 'SHORT     n=' _n_ ' a=[' a '] b=[' b ']';
datalines;
AB
CDEFGH
;
run;

/* BUG-dlmmultichar: INFILE DLM= is a LIST of single-char delimiters — EACH byte
   is an independent delimiter, not just the first. `dlm='|;'` must split a record
   on '|' AND ';'. (Previously only the first char was used; the rest fell into the
   data.) DLMSTR= — the distinct one-multi-char-delimiter form — stays fail-loud.
   Locks three cases: multichar split, single-char narrowing, DSD-missing. (no PHI) */
data multi;
  infile datalines dlm='|;';
  input x $ y $ z $;
datalines;
alpha|beta;gamma
one|two;three
;
run;
proc print data=multi noobs; run;

/* Narrowing lock: single-char DLM=',' must NOT treat ';' as a delimiter — the
   ';' stays inside the field. */
data single;
  infile datalines dlm=',';
  input p $ q $;
datalines;
a;b,c
;
run;
proc print data=single noobs; run;

/* DSD + multichar set: consecutive (different) delimiters read as missing. */
data dsdmc;
  infile datalines dsd dlm='|;';
  input a b c;
datalines;
1|;3
;
run;
proc print data=dsdmc noobs; run;

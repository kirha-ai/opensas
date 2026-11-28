/* BESTFMT-enotation (GH#46 follow-up): a LENGTH-5-truncated 36.6 becomes the
   high-precision double 36.59999990463257. Its DEFAULT numeric display (BEST12)
   and explicit BESTw. must show the full decimal that fits the field, NOT flip
   to E-notation (`3.66E1`). SAS 9.4 uses E-notation only when a plain decimal
   cannot show the magnitude (integer part overflows the width, or rounds to 0). */
data _null_;
  length x 5;
  x = 36.6;
  put 'default=' x;
  put 'best12=' x best12.;
  put 'best6=' x best6.;
  put 'best17=' x best17.;
  /* OPENSAS REGRESSION PIN, not a SAS expectation (STAT-BEST-001): BEST17. now
     shows 16 characters, so the full LENGTH-5 double is pinned by its bits
     (36.59999990463257). SAS 9.4 does not shorten a DATA _NULL_ PDV value, so
     real SAS prints 36.6 here and 40424CCCCCCCCCCD. */
  put 'bits=' x hex16.;
run;

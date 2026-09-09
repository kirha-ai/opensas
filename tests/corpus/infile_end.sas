/* FEAT-infileend (qa tick147): INFILE END=var — a temporary flag, 1 when the
   current read consumes the last record, else 0. Dropped from the output like
   _N_/SET end=.

   REVERT-infileendmultirec: THE TWO BLOCKS BELOW NOW DIFFER, and that contrast
   is the whole point of keeping them in one fixture. Block 1 reads DATALINES,
   where Statements ref printed p.138 puts UNBUFFERED unconditionally in effect
   and "SAS never sets the END= variable to 1" — so `flag` is 0,0,0 including
   on the last record. Block 2 reads an EXTERNAL file with a single INPUT,
   which p.130's Restriction does not cover, so `seen` stays 0,0,1 and MUST NOT
   move: it is the only place the flag is pinned actually reaching 1, because
   the io-free unit fixture can open nothing but DATALINES. If a future change
   moves block 2, END= has broken where it is legal. */
data flags;
  infile datalines end=eof;
  input x;
  flag = eof;
datalines;
10
20
30
;
run;
proc print data=flags noobs; run;

/* same flag on a real external infile */
data ext;
  infile "tests/corpus/infile_end_data.dat" end=last;
  input y;
  seen = last;
run;
proc print data=ext noobs; run;

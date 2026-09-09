/* Retained CHAR values computed by string functions must survive the DATA-step
   row boundary: eval temporaries live in a per-iteration scratch arena reset
   between rows (BUG-datastepoom), so a retained cell must own its bytes across
   iterations. Lag of a computed char exercises the FIFO's state-arena dupe. */
data _null_;
  input x $ n;
  length keepv $10 prevc $10;
  retain keepv;
  if n = 1 then keepv = upcase(strip(x)) || '-K';
  prevc = lag(compress(x || '#'));
  put _n_= keepv= prevc= x=;
  datalines;
aa 1
bb 2
cc 3
;
run;

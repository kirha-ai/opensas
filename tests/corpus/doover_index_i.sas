/* BUG-dooverindex: DO OVER's implicit index is SAS's automatic `_I_` (readable
   in the body) and is NOT emitted as an output column (no `_dooverK_` leak). */
data a; array v{3} v1-v3 (5 6 7);
  last=0;
  do over v; last=_i_; end;
  output;
run;
proc print data=a; run;

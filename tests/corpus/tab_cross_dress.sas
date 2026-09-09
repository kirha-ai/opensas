/* GAP-tabulateopts (QA tick176): the 2-way CROSS path (runTabulateCross) also
   honors ORDER=/LABEL/KEYLABEL and the TABLE `/ box='…'` corner text — a distinct
   code path from the 1-way fixture (tab_order_label). ORDER=DATA keeps the row
   levels in first-appearance order (a then b); LABEL heads the row column; KEYLABEL
   renames the Sum heading under every column-class level; box fills the corner. */
data d;
  input g $ h $ v;
  datalines;
a x 1
a y 2
b x 3
b y 4
;
run;
proc tabulate data=d order=data;
  class g h;
  var v;
  label g='Grp';
  keylabel sum='Ttl';
  table g, h*v*sum / box='corner';
run;

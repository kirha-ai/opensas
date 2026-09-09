/* BUG-inputlinehighwater: a BACKWARD #n line pointer revisits an earlier record
   of the group (Language Reference: Concepts Table 21.5 p.516 — #n is random-access within the record
   group). The step must release the whole HIGH-WATER window, not the final
   cursor position — else the group collapses to one record: a sliding window of
   2-3x too many observations plus a fabricated EOF row. */
data _null_;
  input #2 y #1 x;
  put 'W2 n=' _n_ ' x=' x ' y=' y;
datalines;
1
2
3
4
5
6
;
run;

data _null_;
  input #3 z #1 x;
  put 'W3 n=' _n_ ' x=' x ' z=' z;
datalines;
1
2
3
4
5
6
;
run;

data _null_;
  input x / y #1 z;
  put 'SL n=' _n_ ' x=' x ' y=' y ' z=' z;
datalines;
1
2
3
4
;
run;

data _null_;
  infile datalines dlm=',';
  input #2 y $ #1 x $;
  put 'DLM n=' _n_ ' x=[' x '] y=[' y ']';
datalines;
1,one
2,two
3,three
4,four
;
run;

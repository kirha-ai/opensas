/* GH#46: numeric LENGTH<8 stores the high N bytes of the 8-byte IEEE double
   (deliberate precision loss), and HEXw. with w>=16 shows the raw IEEE bytes.
   x8 has the default length 8 (full precision); x5/x4/x3 are truncated. The
   16.10 column shows the visible precision loss; hex16. shows the exact bytes. */
data a;
  length x5 5 x4 4 x3 3;
  x8 = 36.6;
  x5 = 36.6;
  x4 = 36.6;
  x3 = 36.6;
run;
data _null_;
  set a;
  put 'x8=' x8 16.10 ' hex=' x8 hex16.;
  put 'x5=' x5 16.10 ' hex=' x5 hex16.;
  put 'x4=' x4 16.10 ' hex=' x4 hex16.;
  put 'x3=' x3 16.10 ' hex=' x3 hex16.;
run;

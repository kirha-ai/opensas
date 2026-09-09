/* BUG-translatepairs (tick151): TRANSLATE applies ALL to/from pairs in
   sequence. pair1 to='xy' from='ab': a->x,b->y; pair2 to='z' from='AB':
   A->z, B->blank (to shorter than from pads with blank). -> "xycz C".
   Single-pair control must stay byte-identical. */
data _null_;
  r2 = translate('abcABC', 'xy', 'ab', 'z', 'AB');
  r1 = translate('abcabc', 'XY', 'ab');
  put "r2=[" r2 "]";
  put "r1=[" r1 "]";
run;

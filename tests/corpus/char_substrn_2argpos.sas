/* BUG-substrn2argpos: 2-arg SUBSTRN with nonpositive pos returns from the
   string start to the end; 3-arg window clamp unchanged. */
data _null_;
  a = substrn('abcde',-3);   put "a=[" a "]";  /* [abcde] */
  b = substrn('abcde',0);    put "b=[" b "]";  /* [abcde] */
  c = substrn('abcde',2);    put "c=[" c "]";  /* [bcde]  */
  d = substrn('abcde',6);    put "d=[" d "]";  /* [] past end */
  e = substrn('abcde',-1,3); put "e=[" e "]";  /* [a] window clamp */
  f = substrn('abcde',2,3);  put "f=[" f "]";  /* [bcd] 3-arg control */
run;

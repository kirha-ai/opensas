/* BUG-quoteinformat: $QUOTEw. strips one matched pair of surrounding quotes;
   $HEXw. (char) decodes hex-digit pairs to bytes. Both the INPUT() function
   and the INPUT statement paths. */
data a;
  length fq fh sq sh $20;
  /* INPUT() function form */
  fq = input(quote("hi"), $quote20.);  /* hi   */
  fh = input("414243",   $hex6.);      /* ABC  */
  /* INPUT statement form */
  input sq $quote10. / sh $hex10.;     /* hey / Hello */
  put "fq=" fq " fh=" fh " sq=" sq " sh=" sh;
  datalines;
"hey"
48656C6C6F
;
run;

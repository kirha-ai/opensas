/* %sysfunc breadth — the common wrapped functions used in SDTM driver macros
   (string/date/numeric + compress modifiers). Deterministic. macro-sysfunccompress. */
data _null_; length s $24;
  s="%sysfunc(catx(-,a,b,c))";         put "catx=[" s "]";
  s="%sysfunc(tranwrd(aXbX,X,-))";     put "tranwrd=[" s "]";
  s="%sysfunc(compress(a1b2c3,,kd))";  put "compress_kd=[" s "]";
  s="%sysfunc(compress(a-b-c,-))";     put "compress_chars=[" s "]";
  s="%sysfunc(reverse(abcd))";         put "reverse=[" s "]";
  s="%sysfunc(count(abcabc,a))";       put "count=[" s "]";
  s="%sysfunc(propcase(john q doe))";  put "propcase=[" s "]";
  s="%sysfunc(coalescec(,x,y))";       put "coalescec=[" s "]";
  s="%sysfunc(year(21915))";           put "year=[" s "]";
  s="%sysfunc(putn(21915,yymmdd10.))"; put "putn=[" s "]";
run;

/* BUG-scandelim + BUG-scanmodifiers + BUG-findwdefaults + BUG-quotetrailingblank:
   SCAN/COUNTW share ONE ASCII default delimiter set (blank !$%&()*+,-./;<^| —
   tab/CR/LF only via the `s` modifier, never `>`); the class-adder/k modifiers
   are wired into SCAN and COUNTW; FINDW gets the SCAN default set plus its own
   delimiter/modifier/startpos args (INDEXW keeps blank-only); QUOTE preserves
   trailing blanks inside the quotes. */
data _null_;
  a = scan('x>y', 2);                        put "A=[" a "]";   /* '>' not a delim → '' */
  b = scan('a'||'09'x||'b', 2);              put "B=[" b "]";   /* TAB not a delim → '' */
  c = countw('a'||'09'x||'b');               put "C=" c;        /* → 1 */
  d = scan('ab12cd', 2, ' ', 'd');           put "D=[" d "]";   /* d: digits delimit → cd */
  e = scan('a1b2c3', 2, '123', 'k');         put "E=[" e "]";   /* k: keep only 123 → 2 */
  f = countw('ab12cd', ' ', 'd');            put "F=" f;        /* → 2 */
  g = findw('the-cat', 'cat');               put "G=" g;        /* '-' delim → 5 */
  h = findw('the cat sat', 'cat', ' ', 'e'); put "H=" h;        /* e → word number 2 */
  j = findw('the-cat', 'cat', '-', 3);       put "J=" j;        /* startpos 3 → 5 */
  iw = indexw('the-cat', 'cat');             put "IW=" iw;      /* INDEXW blank-only → 0 */
  q = quote('ABC   ');                       put "Q=[" q "]";   /* trailing blanks kept */
run;

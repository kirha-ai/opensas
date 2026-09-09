/* BUG-coloncmplen: `=:` truncates the LONGER operand to the SHORTER one's
   STORAGE length (min of both, Language Reference: Concepts Ch.6 p.129) — not LHS-to-trimmed-length(RHS). */
data _null_;
  a = ("cat" =: "ca");   /* longer LHS cut to 2: "ca"="ca" -> 1 */
  b = ("ca" =: "cat");   /* longer RHS cut to 2: "ca"="ca" -> 1 */
  c = ("cat" =: "dog");  /* non-match -> 0 */
  d = ("cat" =: "ca ");  /* storage len 3 both: "cat" vs "ca " -> 0 */
  put a= b= c= d=;
run;

data _null_;
  length v $10 w $5;
  v = "ABC"; w = "AB";
  e = (v =: w);          /* shorter storage 5: "ABC  " vs "AB   " -> 0 */
  f = (w =: v);          /* symmetric -> 0 */
  g = (v =: "AB");       /* literal len 2: "AB"="AB" -> 1 */
  put e= f= g=;
run;

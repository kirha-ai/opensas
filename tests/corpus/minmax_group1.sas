/* BUG-minmaxprec: `**`, unary +/-, and the minmax operators (><, <>, MIN, MAX)
   are ONE SAS Group I precedence level, evaluated right-to-left. A separate
   left-assoc minmax level silently mis-grouped the direct mixes:
   2 ** 3 <> 4 gave 8 (want 2**(3<>4)=16) and -2 <> 3 gave 3 (want -(2<>3)=-3). */
data _null_;
  a = 2 ** 3 <> 4;      /* 2**(3<>4) = 2**4 = 16, not (2**3)<>4 = 8 */
  b = -2 <> 3;          /* -(2<>3) = -3, not (-2)<>3 = 3 */
  c = 4 <> 1 >< 3;      /* right-to-left: 4<>(1><3) = 4<>1 = 4, not (4<>1)><3 = 3 */
  d = -2 ** 2;          /* unchanged guard: -(2**2) = -4 */
  e = 2 <> 3 ** 2;      /* ** first: 2<>(3**2) = 9 (same either way) */
  f = 2 * 3 <> 4;       /* Group I still binds tighter than *: 2*(3<>4) = 8 */
  g = 2 ** 3 max 4;     /* word form, same group: 2**(3 max 4) = 16 */
  h = . <> -5;          /* missing ranks lowest: max(., -5) = -5 */
  i = 3 >< .;           /* min picks the missing */
  put a= b= c= d= e= f= g= h= i=;
run;

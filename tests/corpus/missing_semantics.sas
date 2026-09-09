/* Missing-value & operator semantics verified against SAS 9.4 LangRef
   ("Expressions" / "Missing Values") — doc-finder-tick153 audit:
   missing propagates through arithmetic (with NOTE), missing sorts below
   every number, special missings order ._ < . < .A < .Z, MIN/MAX operators
   do NOT skip missing (MIN/MAX functions do), SUM fn vs `+`, IN matches
   missing, `**` right-assoc, unary minus below `**`, booleans are numeric. */
data _null_;
  /* propagation */
  p = . + 1; q = . * 5; r = . / 0;
  put p= q= r=;
  /* missing is below every number */
  m1 = . < -99999; put m1=;                       /* 1 */
  /* special-missing ordering and equality */
  o1 = ._ < .; o2 = . < .A; o3 = .A < .Z; o4 = .Z < 0;
  put o1= o2= o3= o4=;                            /* 1 1 1 1 */
  e1 = .A = .A; e2 = .A = .; e3 = .A = .B;
  put e1= e2= e3=;                                /* 1 0 0 */
  /* arithmetic on a special missing yields plain missing */
  a = .A + 1; put a=;                             /* . */
  /* MIN/MAX operators keep missing; MIN/MAX functions skip it */
  x1 = . >< 3;  x2 = . <> 3;  x3 = min(.,3); x4 = max(.,3);
  put x1= x2= x3= x4=;                            /* . 3 3 3 */
  x5 = . >< .A; put x5=;                          /* . (dot below .A) */
  /* SUM function skips missing, `+` propagates */
  s1 = sum(1,.,3); s2 = 1 + . + 3;
  put s1= s2=;                                    /* 4 . */
  /* IN matches missing against missing */
  i1 = . in (.,1); i2 = . not in (1,2);
  put i1= i2=;                                    /* 1 1 */
  /* boolean-as-numeric, precedence, right-assoc **, unary minus under ** */
  b1 = (7 > 1) + 5; b2 = 2**3**2; b3 = -2**2; b4 = 0**0;
  put b1= b2= b3= b4=;                            /* 6 512 -4 1 */
  /* exact float compare: 0.3 is not 0.1+0.2 */
  f1 = 0.3 = 0.1 + 0.2; put f1=;                  /* 0 */
run;

/* doc-finder tick219 — CHARACTER function modifier/edge DEPTH (charfns.zig +
   functions.zig). Locks the verified-CORRECT behavior of the modifier args and
   clamp edges probed this run: SCAN m/negative-count, CATX missing-skip,
   COMPRESS k + class inversion, FINDW e word-number, FINDC backward, VERIFY
   multi/empty set, INDEXC/INDEXW, negative FIND, COUNTC i, TRANSLATE unequal
   pairs, TRANWRD empty target, SUBSTRN positive/3-arg clamps. The SUBSTRN
   2-arg-with-nonpositive-position silent-wrong is documented in the findings
   doc (still broken) and is deliberately NOT asserted here. */
data _null_;
  length s d $20;
  /* SCAN: m keeps empty words; negative count from the right */
  s = scan('a,,b',2,',','m'); d='['||strip(s)||']'; put "scan_m=" d;   /* [] */
  s = scan('a,,b',2,',');     d='['||strip(s)||']'; put "scan_nm=" d;  /* [b] */
  s = scan('a b c',-1);       put "scan_neg1=" s;                      /* c  */
  s = scan('a b c',-2);       put "scan_neg2=" s;                      /* b  */
  s = scan('a b',9);          d='['||strip(s)||']'; put "scan_oob=" d; /* [] */

  /* CATX skips missing/blank args, keeps separator verbatim */
  s = catx('-','a','','b',' ','c'); put "catx=" s;                     /* a-b-c */

  /* COMPRESS k keep-mode + class inversion */
  s = compress('a1b2c3','','kd'); put "cmp_kd=" s;                     /* 123 */
  s = compress('a1b!2','2','kd'); put "cmp_k2d=" s;                    /* 12 */

  /* FINDW e = word number; FINDC backward */
  n = findw('a b cat d','cat',' ','e'); put "findw_e=" n;              /* 3 */
  n = findc('abcdef','bd','b');         put "findc_b=" n;              /* 4 */

  /* VERIFY multi-arg union; empty set -> pos 1 */
  n = verify('abc123','abc','123'); put "ver_u=" n;                    /* 0 */
  n = verify('abc','');             put "ver_e=" n;                    /* 1 */

  /* INDEXC any-of; INDEXW whole-word; negative FIND backward */
  n = indexc('abcdef','xyzc');    put "indexc=" n;                     /* 3 */
  n = indexw('the cat sat','cat');put "indexw=" n;                     /* 5 */
  n = find('abcabc','bc',-4);     put "find_neg=" n;                   /* 2 */

  /* COUNTC case-insensitive; TRANSLATE short 'to' blanks; TRANWRD empty target */
  n = countc('aAbB','a','i');       put "countc_i=" n;                 /* 2 */
  s = translate('abcde','x','abc'); d='['||strip(s)||']'; put "trans=" d; /* [x  de] */
  s = tranwrd('hello','','Z');      put "tranwrd=" s;                  /* hello */

  /* SUBSTRN clamps that ARE correct (positive / 3-arg) */
  s = substrn('abcde',3);    d='['||strip(s)||']'; put "sn_end=" d;    /* [cde] */
  s = substrn('abcde',2,100);d='['||strip(s)||']'; put "sn_big=" d;    /* [bcde] */
  s = substrn('abcde',0,3);  d='['||strip(s)||']'; put "sn_z3=" d;     /* [ab] */
run;

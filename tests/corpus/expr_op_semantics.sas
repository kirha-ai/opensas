/* doc-finder tick216: expression/operator/numeric-comparison semantics VERIFIED
   against SAS 9.4 docs (Language Reference: Concepts Ch.4-6). Locks already-correct behavior:
   - exact numeric equality, no fuzz: 0.1+0.2 ^= 0.3 (Language Reference: Concepts Ch.4/ROUND docs —
     ROUND/COMPFUZZ exist precisely because = is exact)
   - special-missing comparison order ._ < . < .A < .Z < negatives (Table 5.1)
   - MIN/MAX operators >< <> + word mnemonics: Group I, right-to-left
     (Table 6.6, footnote 5's -3><-3 = +3, p.133's .A<>.Z = .Z)
   - chained comparison x<y<z = (x<y) and (y<z) (Table 6.6 footnote 8)
   - comparisons yield 1/0 usable in arithmetic; missing lowest, never propagates
   - IN: comma/space lists, char lists, NOT IN, missing membership
   - colon-modified compare truncates longer operand to shorter length
   - arithmetic: float division, ** right-assoc, -2**2=-4, 0**0=1,
     ROUND half away from zero with fuzz, INT/CEIL/FLOOR fuzz, MOD dividend sign */
data _null_;
  a01 = (0.1+0.2 = 0.3);   /* 0: exact, no fuzz */
  a02 = (0.3 = 0.3);       /* 1 */
  a03 = (._ < .);          /* 1 */
  a04 = (. < .A);          /* 1 */
  a05 = (.A < .Z);         /* 1 */
  a06 = (.Z < -1e307);     /* 1 */
  a07 = (.A = .);          /* 0 */
  a08 = (. = .);           /* 1 */
  a09 = (. < 5);           /* 1 */
  a10 = 5*(2<3)+12*(2>=3); /* 5 (Language Reference: Concepts p.128 example) */
  a11 = 5 >< 3;            /* 3 */
  a12 = 5 <> 3;            /* 5 */
  a13 = 2 ** 3 <> 4;       /* 2**(3<>4) = 16 */
  a14 = -3><-3;            /* -(3><-3) = +3 (doc footnote 5) */
  a15 = 5 min 3;           /* 3 (MIN is the documented mnemonic for ><) */
  a16 = 5 >< .;            /* . : missing is lowest, wins the min */
  a17 = 5 <> .;            /* 5 */
  a18 = (5 > 4 > 3);       /* (5>4) and (4>3) = 1 (doc footnote 8) */
  a19 = (not .);           /* 1 */
  a20 = (. or 0);          /* 0 */
  a21 = (2 in (1,2,3));    /* 1 */
  a22 = (4 not in (1:3));  /* 1 (integer boundary: both range readings agree) */
  a23 = (3 in (1:3));      /* 1 */
  a24 = ('B' in ('A','B'));/* 1 */
  a25 = (. in (1,.));      /* 1 */
  a26 = ('ca' =: 'cat');   /* 1: longer truncated to shorter */
  a27 = ('Test' ^=: 'T');  /* 0 */
  a28 = 7/2;               /* 3.5 */
  a29 = -2**2;             /* -4 */
  a30 = 2**3**2;           /* 512 */
  a31 = 0**0;              /* 1 */
  a32 = round(2.5);        /* 3: half away from zero */
  a33 = round(-2.5);       /* -3 */
  a34 = rounde(2.5);       /* 2: ties to even */
  a35 = round(1.045, 0.01);/* 1.05: fuzzed boundary rounds up */
  a36 = int(0.3/0.1);      /* 3: fuzz snap */
  a37 = mod(0.3, 0.1);     /* 0: SAS MOD fuzz */
  a38 = mod(-10, 3);       /* -1: sign of dividend */
  a39 = 1/0;               /* . (NOTE + _ERROR_ on stderr) */
  a40 = (0 and 1/0);       /* 0 — but no short-circuit: div NOTE still fires */
  put a01= a02= a03= a04= a05= a06= a07= a08= a09= a10=
      a11= a12= a13= a14= a15= a16= a17= a18= a19= a20=
      a21= a22= a23= a24= a25= a26= a27= a28= a29= a30=
      a31= a32= a33= a34= a35= a36= a37= a38= a39= a40=;
run;

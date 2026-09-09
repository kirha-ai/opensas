/* BUG-execmissdistinct: special missings are DISTINCT values in SAS — exec.zig
   collapsed every NaN into one bucket for hash keys and MERGE BY (.A equaled .).
   Rank ._ < . < .A < ... < .Z < numbers (Language Reference: Concepts p.107 / Table 5.1).
   SQL-side twin: BUG-sqlmissdistinct (e6a705c). */

/* 1. hash lookup: . must NOT match .A's key (rc=160038 not-found, not 0). */
data _null_;
  declare hash h();
  h.defineKey('k'); h.defineData('v'); h.defineDone();
  length v $8;
  k = .A; v = 'A-key'; h.add();
  k = .;  rc = h.check(); put rc=;
  k = .A; rc = h.check(); put rc=;
  k = .Z; rc = h.check(); put rc=;
run;

/* 2. ordered hash: all 5 keys survive (no missing collapse) and iterate in
      rank order ._ < . < .A < -1 < 5. */
data _null_;
  declare hash h2(ordered: 'a');
  h2.defineKey('k'); h2.defineData('k'); h2.defineDone();
  k = 5;  h2.add();
  k = .A; h2.add();
  k = .;  h2.add();
  k = ._; h2.add();
  k = -1; h2.add();
  declare hiter it('h2');
  rc = 0; /* plain assign so the compile-time uninit scan knows rc (spuriousnote) */
  rc = it.first();
  do while (rc = 0);
    put k=;
    rc = it.next();
  end;
run;

/* 3. MERGE BY: .A matches .A, plain . does not (a sorted: . ranks below .A). */
data a; input k v; datalines;
. 2
.A 1
;
run;
data b; input k w; datalines;
.A 10
;
run;
data m;
  merge a b;
  by k;
  put k= v= w=;
run;

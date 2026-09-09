/* BUG-sqlcolwidthloss — a column's DECLARED char width survives PROC SQL.

   The SQL row loader used to bind column values into the PDV with the name and
   type only, dropping the column's declared LENGTH, so the two surfaces
   disagreed about the same column:  lengthc(b) = 4 in a DATA step, 2 in PROC
   SQL, for the same `$4` column holding 'AB'.

   SQL Procedure User's Guide, printed p.37 ("Specifying Column Attributes")
   lists LENGTH= as one of four column attributes and settles the default:
     "If you do not specify these attributes, then PROC SQL uses attributes that
      are already saved in the table or, if no attributes are saved, then it uses
      the default attributes."
   So a SELECTed column keeps its saved width — under an alias too — and an
   explicit SELECT `length=n` (printed p.368) overrides it. opensas stores char
   values UNPADDED where SAS blank-pads to the declared length (printed p.362,
   BTRIM note: a length-10 variable holding 'xxabcxx' is stored "with three
   blanks after the last x"), so the width rides as the variable's own length.

   The volume assigns NO width to a derived column, so none is invented here:
   a computed expression, an aggregate, a CASE result and a literal are
   DOC-SILENT and keep opensas's value-derived width. Each is pinned below so
   the distinction is a decision, not a drift. */

data src;
  length a $3 b $4 c $10 n 8;
  a='ABC'; b='AB'; c='hello'; n=1; output;
run;

/* ── the ticket: the SAME column, both surfaces, side by side ───────────── */
data _null_; set src;
  la=lengthc(a); lb=lengthc(b); lc=lengthc(c);
  va=vlength(a); vb=vlength(b); vc=vlength(c);
  put 'DATA lengthc  a=' la ' b=' lb ' c=' lc;
  put 'DATA vlength  a=' va ' b=' vb ' c=' vc;
  /* LENGTH/LENGTHN are the USED length and stay value-based on both surfaces */
  na=length(a); nb=length(b); nc=length(c);
  put 'DATA length   a=' na ' b=' nb ' c=' nc;
run;

proc sql;
  select lengthc(a) as la, lengthc(b) as lb, lengthc(c) as lc from src;
  select vlength(a) as va, vlength(b) as vb, vlength(c) as vc from src;
  select length(a)  as na, length(b)  as nb, length(c)  as nc from src;
quit;

/* ── per column SOURCE: which width does each kind of SELECT item carry? ── */
proc sql;
  /* a plain column, and the same column under an alias — p.37: 4 and 4 */
  select lengthc(b) as plain, lengthc(bb) as aliased from
    (select b, b as bb from src);
  /* an explicit LENGTH= overrides the saved width — p.368: 2 */
  select lengthc(b) as with_len from (select b length=2 from src);
  /* DOC-SILENT: computed / aggregate / CASE / literal keep the value width.
     One query each — mixing an aggregate with a char expression takes the
     remerge path, whose char computed columns are typed numeric today (a
     separate pre-existing defect: it renders BEST12, filed not pinned). */
  select lengthc(ub) as computed  from (select upcase(b) as ub from src);
  select lengthc(mb) as aggregate from (select max(b) as mb from src);
  select lengthc(fl) as case_arm  from
    (select case when b='AB' then 'yes' else 'no' end as fl from src);
  select lengthc(li) as literal   from (select 'LIT' as li from src);
  /* a NUMERIC declared length is a byte length, never a char width (GH#59) */
  select vlength(n) as vn from src;
quit;

/* ── the width survives CREATE TABLE, so a later DATA step sees it too ─── */
proc sql;
  create table copied as select a, b as bb, c from src;
quit;
proc contents data=copied; run;
data _null_; set copied;
  x1=lengthc(a); x2=lengthc(bb); x3=lengthc(c);
  put 'AFTER lengthc a=' x1 ' bb=' x2 ' c=' x3;
run;

/* ── `||` keeps the declared width's trailing blanks on BOTH surfaces ──── */
/* SQL Procedure printed p.218 is explicit that PROC SQL needs TRIM for this:
   "the SELECT clause uses the TRIM function to remove trailing spaces from the
   data in the FirstName column, and then concatenates the data with a single
   space" — the blanks ride into the concatenation unless trimmed. Same rule as
   the DATA step's (Language Reference: Concepts p.49, BUG-concatnopad). */
data _null_; set src;
  cat = b||'!'; tr = trim(b)||'!';
  put 'DATA concat=[' cat '] trimmed=[' tr ']';
run;
proc sql;
  select b||'!' as cat, trim(b)||'!' as tr from src;
quit;

/* ── CONTROL: the truncated-comparison operators must NOT move ─────────── */
/* Printed p.405 states both surfaces' rules in one sentence and assigns each:
   "The Base SAS WHERE processor truncates comparisons based on the actual
    length of a string, even if a string includes blanks at the end. PROC SQL
    trims trailing blanks from the string values before it truncates
    comparisons."
   The divergence is reachable on COLUMN operands and stays reachable: the DATA
   step's `=:` reads b's declared width (4 -> compares 'ABC' with 'AB ' -> 0)
   while PROC SQL's EQT trims first (2 -> compares 'AB' with 'AB' -> 1). Only
   the DATA-step half consults the width this fixture restores, and it already
   had it, so both halves are unchanged — pinned here so a future width change
   cannot move them silently (NOTE-sqltruncblanks, 8fb0467b). */
data _null_; set src;
  e1=(a =: b); e2=(a >: b); e3=(a <: b); e4=(a >=: b); e5=(a <=: b); e6=(a ^=: b);
  put 'DATA trunc ' e1 e2 e3 e4 e5 e6;
run;
proc sql;
  select (a eqt b) as e1, (a gtt b) as e2, (a ltt b) as e3,
         (a get b) as e4, (a let b) as e5, (a net b) as e6 from src;
quit;

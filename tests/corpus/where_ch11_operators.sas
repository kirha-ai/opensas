/* Language Reference: Concepts Ch.11 "WHERE-Expression Processing" — the doc's own worked rules that
   opensas gets right (doc-finder tick291). Each block cites the book page.
   Deliberately excludes LIKE (BUG-charfixedwidth would move the golden) and
   expression-bounded BETWEEN / multi-token CONTAINS (open tick291 findings). */

/* p.227 "Processing Compound Expressions": NOT, then AND, then OR — so with no
   parentheses this means product='GRAPH' OR (product='STAT' AND country='Canada'). */
data sites;
  length product $6 country $6;
  input product $ country $;
  datalines;
GRAPH USA
STAT  Canada
GRAPH Canada
STAT  USA
BASE  Canada
;
run;
proc print data=sites noobs;
  where product='GRAPH' or product='STAT' and country='Canada';
run;
/* p.227 "Using Parentheses to Control Order of Evaluation" — the doc's fix. */
proc print data=sites noobs;
  where (product='GRAPH' or product='STAT') and country='Canada';
run;

data emp;
  input empnum;
  datalines;
100
500
750
1000
1500
;
run;
/* p.220 "Fully Bounded Range Condition" + p.221 "Note: the BETWEEN-AND operator
   and a fully bounded range condition produce the same results". */
proc print data=emp noobs;
  where 500 <= empnum <= 1000;
run;
proc print data=emp noobs;
  where empnum between 500 and 1000;
run;
/* p.220 "You can combine the NOT logical operator with a fully bounded range
   condition ... Note that parentheses are required" + p.221 NOT BETWEEN. */
proc print data=emp noobs;
  where not (500 <= empnum <= 1000);
run;
proc print data=emp noobs;
  where empnum not between 500 and 1000;
run;

data st;
  length state $2;
  input state $ n;
  datalines;
NC 1
TX 2
CA 3
TN 4
MA 5
;
run;
/* p.220 "IN Operator": the list values are "separated by either a comma or
   blank"; NOT excludes a list; "M:N" is a range of sequential integers. */
proc print data=st noobs;
  where state in ('NC','TX');
run;
proc print data=st noobs;
  where state in ('NC' 'TX');
run;
proc print data=st noobs;
  where state not in ('CA', 'TN', 'MA');
run;
proc print data=st noobs;
  where n in (2:4);
run;

/* p.222 "IS NULL or IS MISSING Operator": selects both regular AND special
   missing values, for character and numeric variables; `where idnum <= .Z` is
   the documented numeric equivalent; NOT selects the nonmissing values. */
data pat;
  length name $6;
  idnum=1;  name='Alice'; output;
  idnum=.;  name='Bob';   output;
  idnum=2;  name=' ';     output;
  idnum=.a; name='Dave';  output;
  idnum=.z; name='Eve';   output;
run;
data _null_;
  set pat;
  where name is null;
  put 'ISNULL   name=[' name ']';
run;
data _null_;
  set pat;
  where idnum is missing;
  put 'ISMISS   idnum=' idnum;
run;
data _null_;
  set pat;
  where idnum <= .Z;
  put 'LEDOTZ   idnum=' idnum;
run;
data _null_;
  set pat;
  where idnum is not missing;
  put 'NOTMISS  idnum=' idnum;
run;

/* p.224 "Sounds-like Operator": the doc's list selects every name except
   Smithson. p.219 colon modifier: `=:` compares only the given prefix.
   p.225 Note: "<> is interpreted as not equal to" in a WHERE expression. */
data nm;
  length lastname $10;
  input lastname $;
  datalines;
Schmitt
Smith
Smithson
Smitt
Smythe
;
run;
data _null_;
  set nm;
  where lastname =* 'Smith';
  put 'SOUNDS   ' lastname;
run;
data _null_;
  set nm;
  where lastname =: 'Smit';
  put 'PREFIX   ' lastname;
run;
data _null_;
  set nm;
  where lastname <> 'Smith';
  put 'NEBRACK  ' lastname;
run;

/* p.216 "Specifying an Operand": a bare NUMERIC variable name stands alone and
   is true when it is neither missing nor zero. */
data flags;
  length who $8;
  input empnum id who $;
  datalines;
1 1 Alpha
0 1 Beta
. 1 Gamma
2 0 Delta
3 . Epsilon
;
run;
data _null_;
  set flags;
  where empnum and id;
  put 'BARENUM  ' who;
run;

/* p.216: a SAS function is a valid WHERE operand. */
data sites;
  length invest $12 town $12;
  input invest $ town $;
  datalines;
VanHouten Lyon
VanDyke Turin
Okafor Lyon
VanBuren Porto
;
run;
data testvans;
   set sites;
   where substr (invest,1,3) = 'Van' and
   (town='Lyon' or town='Turin');
run;
proc print data=testvans noobs;
run;

/* p.231 "Deciding Whether to Use a WHERE Expression or a Subsetting IF
   Statement": WHERE tests the condition BEFORE the observation is read into the
   PDV, so BY-group FIRST./LAST. see the FILTERED stream, not the raw one. */
data grp;
  input g x;
  datalines;
1 1
1 2
1 3
2 4
2 5
;
run;
data _null_;
  set grp;
  by g;
  where x ne 1;
  put 'BYFILT   g=' g ' x=' x ' first=' first.g ' last=' last.g;
run;

/* p.216's "you cannot use automatic variables created by the DATA step" rule
   (WHERE on _N_ / FIRST.var / an assigned variable) is deliberately NOT pinned
   here: opensas fails loud on stderr, which the corpus runner does not diff. */

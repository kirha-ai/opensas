/* BUG-macroscandelim: a delimiter quoted with %str/%quote/%bquote arrived at the
   macro functions as the mask_comma SENTINEL, and every consumer there BYTE-COMPARES
   its args — so %scan searched for 0x03, never found it, and returned "" where SAS
   returns the word. %str(,) is THE idiom for a comma delimiter (an unquoted comma
   would split the argument list itself), so this broke the standard way of doing a
   very common thing, silently and with a wrong value rather than an error.
   Fixed at the ARGUMENT BOUNDARY (unmaskTriggers over every macro-fn arg), which is
   what %sysfunc already did one function over — so the sibling byte-comparers below
   (%index needle, %verify excerpt) and the MIRROR direction (a masked SUBJECT never
   split on a plain delimiter either) are all covered by the one fix.
   The last block pins the Q-vs-plain result contract that the fix must not break:
   %qsubstr's comma stays MASKED, so catx uses it as a literal delimiter (a,b), while
   plain %substr returns it LIVE, so it splits catx's own argument list (ab) — the
   same rule %qsysfunc/%sysfunc already follow. */
%macro two(x,y); [x=&x|y=&y] %mend;
%let s = a,b c,d;
%let m = %str(a,b);
data _null_;
  /* the reported shape — both the Q and plain forms */
  put "qscan1     =[%qscan(&s,1,%str(,))]";
  put "qscan2     =[%qscan(&s,2,%str(,))]";
  put "scan2      =[%scan(&s,2,%str(,))]";
  put "scanlast   =[%qscan(&s,-1,%str(,))]";
  /* %quote/%bquote mask the same way %str does */
  put "quotedelim =[%scan(&s,2,%quote(,))]";
  put "bquotedelim=[%scan(&s,3,%bquote(,))]";
  /* siblings that byte-compare the same masked arg */
  put "index      =[%index(&s,%str(,))]";
  put "verify     =[%verify(&s,%str(a,bcd ))]";
  /* mirror direction: the SUBJECT is masked, the delimiter is plain */
  put "masksubj   =[%scan(&m,2,%str(,))]";
  put "masksubjdef=[%scan(&m,2)]";
  /* unmasked delimiters must be untouched by the fix */
  put "plaindelim =[%scan(a-b-c,2,-)]";
  put "nosuchdelim=[%scan(&s,2,%str(-))]";
  /* the Q result stays masked; the plain result does not (see header) */
  put "qmasked    =[%sysfunc(catx(%qsubstr(%str(*,*),2,1),a,b))]";
  put "plainlive  =[%sysfunc(catx(%substr(%str(*,*),2,1),a,b))]";
  put "strbaseline=[%sysfunc(catx(%str(,),a,b))]";
  /* the pre-existing Q contract: a masked & survives the Q form unresolved */
  put "qampstays  =[%qscan(%nrstr(x&b|y),1,|)]";
run;

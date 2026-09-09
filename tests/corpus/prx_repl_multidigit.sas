/* doc-finder tick199 (GAP-prxrepldoubledigit): an s/// replacement reference
   $num is MULTI-digit — SAS 9.4 Functions and CALL Routines: Reference,
   Appendix 1 PRX metacharacter table (printed p.1713): "\num  $num  matches
   capture buffer num, where num is a positive integer". opensas read ONE
   digit, so $10 rendered group 1 + a literal "0". The pattern side of this
   same engine already parses \num greedily and ERRORs on a reference past the
   last group (verified: /(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)\10/ matches
   "abcdefghijj", not "abcdefghija0"; \10 with 5 groups logs "invalid back
   reference"). The replacement now follows the SAME rule — one engine, one
   meaning for a group number: $10 with only 5 groups is a LOUD compile ERROR
   (prxparse returns missing), never group-1-plus-literal and never silent
   empty text. */
data _null_;
  s = 'abcdefghijkl';
  rx = prxparse('s/(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)/$10-$1/');
  t = s; call prxchange(rx, -1, t);
  put "dollar10=[" t "]";   /* [j-akl] — group 10, not group 1 + "0" */

  /* controls: $1 through $9 unchanged */
  rx2 = prxparse('s/(a)(b)(c)(d)(e)(f)(g)(h)(i)/$9$8$7$6$5$4$3$2$1/');
  t2 = 'abcdefghi'; call prxchange(rx2, -1, t2);
  put "controls=[" t2 "]";  /* [ihgfedcba] */

  /* $0 = whole match (unchanged) */
  rx3 = prxparse('s/(a)(b)/[$0]/');
  t3 = 'ab'; call prxchange(rx3, -1, t3);
  put "dollar0=[" t3 "]";   /* [[ab]] */

  /* ambiguous case: $10 with only 5 groups -> LOUD ERROR on stderr, rx=. */
  rx4 = prxparse('s/(a)(b)(c)(d)(e)/$10/');
  put "bad10=" rx4;

  /* non-existent group: $2 with one group -> LOUD ERROR on stderr, rx=. */
  rx5 = prxparse('s/(a)/$2/');
  put "bad2=" rx5;
run;

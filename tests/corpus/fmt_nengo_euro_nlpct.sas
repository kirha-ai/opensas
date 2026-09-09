/* GAP-fmtwrite-unimpl (remainder) — the last two write-side format groups.
   NENGOw. (SAS 9.4 Formats Reference p.257): Japanese era date `e.yymmdd`;
   the five documented widths of the entry's own example (15342 = 02JAN2002
   = Heisei 14), the era boundaries (Showa 64 ends 07JAN1989, Heisei 1 begins
   08JAN1989; Heisei 31 ends 30APR2019, Reiwa 1 begins 01MAY2019; Meiji 45
   ends 29JUL1912, Taisho 1 begins 30JUL1912), pre-Meiji → asterisks (doc
   silent), missing → left-justified dot (Alignment: Left).
   EUROw.d/EUROXw.d (pp.215/218): NOT locale-driven — the DOLLAR/DOLLARX
   twins with a leading E; the w=6 default-length log's fit ladder drops the
   SYMBOL before the grouping (55,555 not E55555), BESTw separators NOT
   swapped under EUROX (7.78E6).
   NLPCTIw.d (p.417) / NLPCTNw.d (p.418): the two locale-INVARIANT percent
   formats — NLPCTI's comma/period separators are pinned by the Comparisons
   paragraph and shown identical under en_US and German_Germany in the NLPCT
   entry's own example; NLPCTN has no separators and a documented trailing
   blank (p.418 Tip).
   STILL LOUD (parked): NLPCT (p.415) and NLPCTP (p.419) have locale-specific
   separators; NLMNYI's (p.410) international-code position is locale-dependent;
   every NLMNI<ccy> entry says "The output value depends on the locale" —
   opensas has no LOCALE= option, so any rendering would be a guessed symbol.
   YEN does not exist in the 9.4 reference at all (D-015).
   GAP-gapsexitingone §5f (D-009): the parked names are DOCUMENTED SAS 9.4
   formats, so their refusal is an opensas gap and this program now exits 2 —
   a legitimate golden change from the old rc-1 pin, the rc the epic exists
   to fix (rc 1 told a downstream agent to "fix" valid SAS). YEN stays an
   rc-1 typo; its arm is pinned separately in rc_fmt_bogus_typo.sas (one run,
   one rc).
   expect-rc: 2 */
data _null_;
  length s $40;
  s = put(15342, nengo3.);  put "nengo3=[" s "]";
  s = put(15342, nengo6.);  put "nengo6=[" s "]";
  s = put(15342, nengo8.);  put "nengo8=[" s "]";
  s = put(15342, nengo9.);  put "nengo9=[" s "]";
  s = put(15342, nengo10.); put "nengo10=[" s "]";
  s = put(15342, nengo.);   put "nengodef=[" s "]";
  s = put(15342, nengo12.); put "nengo12=[" s "]";
  s = put('07JAN1989'd, nengo10.); put "showa64=[" s "]";
  s = put('08JAN1989'd, nengo10.); put "heisei1=[" s "]";
  s = put('30APR2019'd, nengo10.); put "heisei31=[" s "]";
  s = put('01MAY2019'd, nengo10.); put "reiwa1=[" s "]";
  s = put('29JUL1912'd, nengo10.); put "meiji45=[" s "]";
  s = put('30JUL1912'd, nengo10.); put "taisho1=[" s "]";
  s = put('07SEP1868'd, nengo10.); put "premeiji=[" s "]";
  s = put(., nengo10.); put "nengomiss=[" s "]";
  s = put(1254.71, euro10.2); put "euro10_2=[" s "]";
  s = put(1254.71, euro5.);   put "euro5=[" s "]";
  s = put(1254.71, euro9.2);  put "euro9_2=[" s "]";
  s = put(1254.71, euro15.3); put "euro15_3=[" s "]";
  s = put(4444, euro.);    put "euro4444=[" s "]";
  s = put(55555, euro.);   put "euro55555=[" s "]";
  s = put(666666, euro.);  put "euro666666=[" s "]";
  s = put(7777777, euro.); put "euro7777777=[" s "]";
  s = put(1254.71, eurox10.2); put "eurox10_2=[" s "]";
  s = put(1254.71, eurox5.);   put "eurox5=[" s "]";
  s = put(4444, eurox.);       put "eurox4444=[" s "]";
  s = put(55555, eurox.);      put "eurox55555=[" s "]";
  s = put(7777777, eurox.);    put "eurox7777777=[" s "]";
  s = put(-12.3456789, nlpcti32.2); put "nlpcti32_2=[" s "]";
  s = put(0.075, nlpcti8.1);        put "nlpcti8_1=[" s "]";
  s = put(0.075, nlpcti.);          put "nlpctidef=[" s "]";
  s = put(-0.02, nlpctn6.);  put "nlpctn6=[" s "]";
  s = put(0.075, nlpctn8.1); put "nlpctn8_1=[" s "]";
  x = 0.5;
  put x nlpct10.2;  /* parked: ERROR to stderr, raw fallback on stdout */
  put x nlpctp10.2;
  put x nlmnyi12.2;
  put x yen8.;
run;

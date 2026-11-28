/* expect-rc: 2
 * STAT-CAUSALGRAPH-008 (Time Requirements, p.2330): limits of the opensas
 * adjustment-set search fail visibly (D-009) instead of truncating: more
 * than 64 measured covariates (u64 set masks), and a covariate table wider
 * than LINESIZE= even with 2-blank column gaps (SAS splits such tables; no
 * reference run). SAS lists both (a 25-covariate listing is compared in
 * stat_causalgraph008_nosort). Invented graphs.
 */
options nosyntaxcheck nodate nonumber nocenter linesize=160 pagesize=max;
proc causalgraph nosort maxlist=1; model 'B' X ==> Y, C1 C2 C3 C4 C5 C6 C7 C8 C9 C10 C11 C12 C13 C14 C15 C16 C17 C18 C19 C20 C21 C22 C23 C24 C25 C26 C27 C28 C29 C30 C31 C32 C33 C34 C35 C36 C37 C38 C39 C40 C41 C42 C43 C44 C45 C46 C47 C48 C49 C50 C51 C52 C53 C54 C55 C56 C57 C58 C59 C60 C61 C62 C63 C64 C65 ==> X Y; identify X ==> Y; run;
options linesize=64;
proc causalgraph; model 'W' X ==> Y, LongCovariateName1 LongCovariateName2 LongCovariateName3 LongCovariateName4 LongCovariateName5 LongCovariateName6 LongCovariateName7 LongCovariateName8 ==> X Y; identify X ==> Y; run;

/* BUG-procmissingfilerc (GH#21) — a DATAFILE= that cannot be read is the
   USER's error, exit 1: their path is wrong or the file was never delivered.
   It used to exit 2, which under the D-009 contract tells a downstream agent
   "opensas cannot do this, file an issue" about a path typo. Twin of exec.zig's
   INFILE open failure, rc 1 since ISS-infilemissing, and of the five
   BUG-procmissingrc2 absent-input arms.

   All FOUR delimited/workbook DBMS values funnel through one io.readFileRaw
   call, so all four must land on the same class — `options nosyntaxcheck;`
   (D-024) keeps the later steps running so this one fixture exercises every
   one of them. The pin is the whole point: a gap OUTRANKS a user error in
   diag.exitCode, so if ANY of the four still marked a gap the run would exit 2
   and this fixture would go red.

   The DBMS gap guard runs BEFORE the read, so an unimplemented DBMS still
   exits 2 (rc_import_option_gap.sas pins that side), and so does a workbook
   that reads fine but will not parse (rc_import_xlsx_parse_gap.sas).

   No step produces output: stdout is empty and the ERRORs go to stderr.
   expect-rc: 1 */
options nosyntaxcheck;

proc import datafile="/no/such/dir/rc_missing.csv" out=a dbms=csv replace;
  getnames=yes;
run;

proc import datafile="/no/such/dir/rc_missing.dat" out=b dbms=dlm replace;
  delimiter=',';
run;

proc import datafile="/no/such/dir/rc_missing.txt" out=c dbms=tab replace;
run;

proc import datafile="/no/such/dir/rc_missing.xlsx" out=d dbms=xlsx replace;
run;

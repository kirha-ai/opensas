# FEAT-odsoutput — dev5, SAS 9.4 M9

Bounded starter capture layer; FEAT-base-stat-results remains separate. D-022
keeps destination rendering inert and SELECT/EXCLUDE/TRACE loud. No listing text
is parsed. All inputs here are synthetic.

## Producer contract

`ProcCtx.capture: ?*ods.Capture = null` preserves direct producer callers.
`Capture.publish(allocator, diagnostics, table_name, *const Dataset)` consumes
owned typed schema/cells, including BY identity. Names match case-insensitively.
The registry unions schemas by column name, fills typed missing cells, widens
character lengths, and retains metadata. `finish` writes through Library.put
(read-only librefs and macro dataset state included) in SAS reverse request
order, warns for absent objects, and expires requests after the next PROC.

Minimal hooks: corr.zig after compute/before render; freq.zig after typed table
construction/before rendering; proc.zig in the existing UNIVARIATE per-variable
computation. Schema adapters live in separate stat/ods_* files. No algorithm
files were rewritten. CORR advanced mode compatibility is checked at landing.

## Supported named-table contract

BY variables precede the following columns, retaining source types, lengths,
formats, informats and labels. Multiple groups/variables/tables concatenate in
producer order. Union columns retain first appearance order.

- CORR `PearsonCorr`: character Variable; optional character Label; numeric
  VAR-named coefficient columns; numeric P<VAR> unless NOPROB; numeric N<VAR>
  when pair counts differ. WITH controls rows. Diagonal p is special missing
  `._`. NOPRINT/NOCORR produce no object.
- CORR `SimpleStats`: character Variable; numeric NObs, Mean, StdDev, Sum, Min,
  Max; optional character Label. NOPRINT/NOSIMPLE produce no object.
- FREQ `OneWayFreqs`: character Table, F_<variable>; typed raw variable;
  numeric Frequency, Percent, CumFrequency, CumPercent. NOPERCENT/NOCUM and
  negative weights remove the corresponding columns as SAS does. MISSPRINT
  retains excluded missing categories with missing percentages. MAXLEVELS and
  NOPRINT govern production. Duplicate/BY names receive numeric suffixes.
- FREQ `CrossTabFreqs`: character Table; typed dimension columns; character
  _TYPE_; numeric _TABLE_, Frequency; requested numeric Expected, Deviation,
  CellChiSquare, TotalPercent; numeric Percent/RowPercent/ColPercent subject
  to display controls; requested CumColPercent; numeric Missing. Cells and
  margins are separate observations; n-way Table labels and _TABLE_ identify
  strata. Negative weights suppress percentage/statistic columns. LIST and
  CROSSLIST produce other objects in SAS, so this request warns/unproduced.
- UNIVARIATE `Moments`: character VarName, Label1, cValue1; numeric nValue1;
  character Label2, cValue2; numeric nValue2. Six rows per analysis variable.
  Character values are independently formatted from full-precision numerics.
- UNIVARIATE `Quantiles`: character VarName, Quantile; numeric Estimate.
  Eleven rows in SAS order from 100% Max through 0% Min.
- UNIVARIATE `BasicMeasures`: character VarName, LocMeasure; numeric LocValue;
  character VarMeasure; numeric VarValue. Four rows, including SAS `._` for
  the blank fourth location measure. UNIVARIATE CLASS columns are formatted
  character columns after VarName. Empty/all-missing and NOPRINT produce no
  captured object. Existing WEIGHT/FREQ/VARDEF/PCTLDEF computation is reused.

Only these seven names are supported. Other named tables, paths, dataset
options, MATCH_ALL/PERSIST and selection/tracing syntax are not silently
accepted. Ambiguous generated schemas fail visibly rather than overwrite cells.
This is not a claim of arbitrary ODS object or destination support.

## Oracle evidence

The schema dump records `Release Created 9.0401M9`. Probes ran with the actual
`/Users/thomas/sas/bin/sasrun`, using dev5-specific absolute temporary filenames.
The corpus fixture was also run with `-f text -o - -l /dev/null`: zero errors,
zero warnings. Retained schema/value evidence uses text output; no PDF scraping.

- schema: all seven schemas, column types and lengths, two BY groups, two
  analysis variables. Rows pc/ss/ow/ct/mo/qu/bm = 4/4/6/32/24/44/16 and columns
  = 6/8/8/11/8/4/6. Pearson xy=.32732683535398, mean=2.33333333333333,
  moments cValue1=2.33333333; exact typed values asserted independently.
- lifecycle: mixed PearsonCorr/Moments requests expire after CORR; C exists,
  M does not even after subsequent UNIVARIATE. Two OneWayFreqs destinations
  both exist. An intervening PRINT expires unmatched requests. Empty input
  creates no dataset. CLASS schema is character, even for numeric classes.
- repeat: BY/TABLES overlap gives b2; x*x gives x2; duplicate destination
  keeps the first request with a warning, not overwrite/union by target.
- last: SYSLAST=WORK.PC for PearsonCorr=pc SimpleStats=ss; WORK.O1 for
  OneWayFreqs=o1 OneWayFreqs=o2. Outputs close in reverse request order.
- options/freqcontrols: suppression columns; Expected/Deviation/CellChiSquare;
  n-way Table text and TotalPercent/CumColPercent; LIST/CROSSLIST do not
  generate CrossTabFreqs. References to deliberately absent datasets in
  these exploratory probes produce expected SAS errors; schema-producing
  procedures themselves succeeded.
- weighted: zero and negative weights; UNIVARIATE extrema still include
  zero-weight observations while interior quantiles use positive weights.
  FREQ negative weights produce 5-column OneWayFreqs and 7-column
  CrossTabFreqs; cumulative counts remain signed. Zero errors/warnings.
- empty: all-missing UNIVARIATE generates none of the three requested objects;
  the exploratory PRINT of the absent dataset deliberately errors.

Early edge/freqcontrols probes also contain malformed diagnostic PUT statements
or PRINTs of absent outputs. They are retained as exploratory evidence, not
represented as green acceptance programs. The clean corpus fixture and typed
regressions are the runnable acceptance checks.

## Regression coverage / tracking

In-process captured-diagnostic tests cover parsing atomically, unsupported names
and syntax, duplicate targets, close/reset, lifecycle, missing objects, typed
schema union with reordered columns/widened characters/BY metadata, incompatible
types, all seven SAS schemas and values, pair counts/labels, CLASS, repeated
FREQ variables and negative weights. The end-to-end corpus fixture exercises
hoisted ODS, BY, multiple requests, and consuming all seven captured datasets.
Its golden preserves opensas listing layout; numeric marker lines are checked
against the SAS run. Expected output is committed separately from implementation.
D-022 and the ODS EBNF are updated; no function tracker applies and jira is untouched.

/* STAT-PLM-001: PROC PLM RESTORE= reads the OpenSAS native item store that
 * PROC GLM STORE wrote in this session; NOINFO leaves only the Class Level
 * Information table and NOPRINT suppresses all output. Data: the published
 * SAS/STAT PLM "Getting Started" block design. The Store Information table
 * carries the wall-clock creation time, so its deterministic layout check
 * lives in src/stat/plm_tests.zig. */
data BlockDesign;
input block a b y @@;
datalines;
1 1 1 56 1 1 2 41
1 2 1 50 1 2 2 36
1 3 1 39 1 3 2 35
2 1 1 30 2 1 2 25
2 2 1 36 2 2 2 28
2 3 1 33 2 3 2 30
3 1 1 32 3 1 2 24
3 2 1 31 3 2 2 27
3 3 1 15 3 3 2 19
4 1 1 30 4 1 2 25
4 2 1 35 4 2 2 30
4 3 1 17 4 3 2 18
;
proc glm data=BlockDesign noprint;
class block a b;
model y = block a b a*b;
store work.BlockAnalysis / label='PLM: Getting Started';
run;
proc plm restore=work.BlockAnalysis noinfo;
run;
proc plm restore=BlockAnalysis noprint;
run;
proc plm restore=BlockAnalysis noinfo noclprint seed=3 alpha=0.1 stmtorder=syntax;
run;

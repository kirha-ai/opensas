# Bounded normalized-coordinate / extended-precision result

**CONCLUSIVE NEGATIVE RESULT FOR THE FROZEN FAMILY.** No raw-selector change is
validated. The landed binned SJPI core and public-path guard remain unchanged.
This does not rule out every possible internal C expression, grid construction,
register allocation, or use of x87 by SAS.

The candidate family and 27 fresh cases were committed before evaluation and
before the fresh oracle run. [FROZEN.md](FROZEN.md) specifies the 90 candidates;
[FROZEN-SHA256.txt](FROZEN-SHA256.txt) locks the model code, generator, manifest
and SAS source. No candidate or fitted tolerance was added after seeing scores.

## Result and validation

- Exact rational arithmetic followed by explicit binary round-to-nearest/even
  models 53-bit and 64-bit significands, six storage schedules and three
  integer conversions. It is a precision model, not an instruction emulator.
- The binary64 model matches **1120/1120** retained native SAS intermediate
  HEX16 values. Exact halfway, negative halfway and double-rounding self-tests
  pass. A retained extended q+.5 and its binary64 spill are explicitly tested
  to give different integer conversions, so the two paths are not conflated.
- **136/136** known assignments are kept. All **27/27** prespecified fresh
  assignments are uniquely resolved by the left/right bandwidth discriminator.
  Fresh max absolute h error is **7.105427357601002e-15**, versus tolerance
  1e-10. No unresolved or reselected heldout is hidden.
- SAS reports **9.04.01M9P06052025**, zero errors and zero warnings for the
  fresh batch. Actual returned HEX16 input bits match the frozen manifest.
- **0/90** models pass all known cases; **0/90** pass all fresh cases.
  The best joint score is **91/136 known + 25/27 fresh = 116/163**.

Best score per storage plan below is descriptive, not an accepted selection:

| Storage plan | Known | Fresh for the known-best candidate |
|---|---:|---:|
| binary64 | 91/136 | 25/27 |
| extended64 | 85/136 | 22/27 |
| extended64_step_store | 85/136 | 22/27 |
| extended64_input_store | 91/136 | 23/27 |
| extended64_q_store | 86/136 | 22/27 |
| extended64_each_store | 91/136 | 25/27 |

All candidate scores, failed-case IDs and explicit counterexamples are in
[combined-results.json](combined-results.json). The native arithmetic match
validates the simulator baseline; it does NOT establish internal C precision.

## Normalized ULP transition map

Define exact q=200*(x-low)/(high-low), h=k+1/2, and delta=(q-h)/ULP53(h).
These calculations use the exact rational values of the actual binary64
inputs. ULP64(h)=ULP53(h)/2048 for this normal-range test set.

Examples from the retained transition probes:

| Prior heldout ID | k | Exact delta in ULP53 | Evaluated binary64 q offset | Evaluated extended64 q offset in ULP64 | Oracle bin |
|---|---:|---:|---:|---:|---:|
| 13 | 87 | -25/32 | -1 | -1600 | 87 |
| 14 | 87 | -25/64 | 0 | -800 | 88 |
| 22 | 62 | -25/8 | -3 | -6400 | 62 |
| 23 | 62 | -25/16 | -2 | -3200 | 63 |

The k=87 pair can be explained in isolation by rounding q to binary64 before
conversion. The k=62 right-bin result cannot be justified by that same local
rounding argument. It is not valid to fit a separate tolerance to each pair.
The full exact map is [combined-normalized.csv](combined-normalized.csv).
Physical-neighbor heldouts have their actual normalized ULP spacings recorded;
they are not mislabeled as uniformly spaced normalized-coordinate neighbors.

## Exact collision: a stronger obstruction than a failed score

Five groups have **identical exact centered operands and index** but opposite
oracle assignments. One particularly simple witness is:

| Known case | low HEX16 | high HEX16 | x HEX16 | Oracle bin |
|---|---|---|---|---:|
| dev2-sjpi-halfgrid:13 | C020000000000000 | 4020000000000000 | BFF0000000000000 | 87 |
| dev2-sjpi-halfgrid:16 | C01FF5C28F5C28F6 | 4020051EB851EB85 | BFEFAE147AE147B0 | 88 |

Both have k=87, exact x-low=7, exact span=16 and exact q=87.5. Subtraction of
these centered operands is exact in both tested precisions. Thus any
deterministic decision that uses ONLY k and these centered operands/q cannot
explain both, regardless of an index-dependent tolerance or additional
significand precision. The collision is not caused by rounded display text.

There are also collisions off the exact midpoint: known case 12 and prior
heldout case 15 share exact q offset **-25/128 ULP53**, yet select opposite
bins. Therefore the obstruction is not confined to a mathematical equality.
The full witnesses, including evaluated 53/64-bit q values, are retained in
the results JSON.

This narrows the unresolved mechanism: a successful selector must preserve
additional absolute-domain/grid-construction information or another internal
path/state not determined by the centered coordinate alone. The frozen
absolute-coordinate division/inverse models also fail, but those failures do
not logically exclude every possible absolute-domain C implementation.

## Independent fresh counterexample

Fresh `heldouts:1` uses k=19, low=-2.125, high=9.875 and target
`BFEE8F5C28F5C28F` (binary64 -0.955). Its exact q is above the half-grid location
by **3/16 ULP53**, or **384 ULP64**. SAS's h=2.131187326977094 agrees with the
left-bin candidate 2.131187326977095; the right-bin candidate is
2.132334372070277. The retained extended64 absolute-division/truncation model
selects the right bin. This is an independently prescribed counterexample,
not a case selected after a hypothesis was fitted.

## Reproduce

```
python3 docs/findings/univ-sjpi-dev2/extended-precision/analyze.py --out /private/tmp/dev2-sjpi-x87-replay
python3 docs/findings/univ-sjpi-dev2/extended-precision/analyze.py --out /private/tmp/dev2-sjpi-x87-replay --require-parity
```

The first command succeeds when the discriminator finishes and validates the
frozen inputs/model. The second intentionally exits 1: no frozen model passes.
This is not a failing production regression or a reason to loosen tolerance.
For the oracle, the exact frozen source was copied to the unique absolute path:

```
/Users/thomas/sas/bin/sasrun /private/tmp/dev2-sjpi-x87-heldouts.sas -f text -o /private/tmp/dev2-sjpi-x87-stage/heldouts.txt -l /private/tmp/dev2-sjpi-x87-stage/heldouts.log
```

The source, output, log, manifest, normalized map and counterexamples are all
retained here. The originally frozen SHA256 values remain unchanged. This
bounded pass is complete; no additional arithmetic fanout or public raw rule
is introduced. The parent raw-selector work remains unaccepted.

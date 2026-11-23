//! Documented table names distinguish unimplemented producers from misspelled or
//! unmatched ODS OUTPUT requests. SAS 9.4 Statistical Procedures tables 2.3,
//! 3.22 and 4.40 supply the procedure-specific names.
const std = @import("std");

const documented = [_][]const u8{
    // CORR
    "Cov",                "CronbachAlpha",             "CronbachAlphaDel",    "Csscp",             "FisherPearsonCorr", "FisherPearsonPartialCorr",
    "FisherSpearmanCorr", "FisherSpearmanPartialCorr", "HoeffdingCorr",       "KendallCorr",       "PartialCov",        "PartialCsscp",
    "PartialKendallCorr", "PartialPearsonCorr",        "PartialSpearmanCorr", "PearsonCorr",       "PolychoricCorr",    "PolyserialCorr",
    "SimpleStats",        "SpearmanCorr",              "Sscp",                "VarInformation",
    // FREQ
       "BarnardsTest",      "Binomial",
    "BinomialCLs",        "BinomialEquiv",             "BinomialEquivLimits", "BinomialEquivTest", "BinomialNoninf",    "BinomialSup",
    "BinomialTest",       "BnMeasure",                 "BreslowDayTest",      "CMH",               "ChiSq",             "CochransQ",
    "ColScores",          "CommonOddsRatioCL",         "CommonOddsRatioTest", "CommonPdiff",       "CommonPdiffTests",  "CommonRelRisks",
    "CrossList",          "CrossTabFreqs",             "EqualKappaTest",      "EqualKappaTests",   "EqualOddsRatios",   "FishersExact",
    "FishersExactMC",     "GailSimonTest",             "Gamma",               "GammaTest",         "I2",                "JTTest",
    "JTTestMC",           "KappaDetails",              "KappaMC",             "KappaStatistics",   "KappaTest",         "KappaWeights",
    "LRChiSq",            "LRChiSqMC",                 "List",                "MHChiSq",           "MHChiSqMC",         "MantelFleiss",
    "McNemarsTest",       "Measures",                  "NLevels",             "OddsRatioCLs",      "OddsRatioExactCL",  "OneWayChiSq",
    "OneWayChiSqMC",      "OneWayFreqs",               "OneWayLRChiSq",       "OverallKappa",      "OverallKappas",     "PdiffCLs",
    "PdiffEquiv",         "PdiffEquivTest",            "PdiffNoninf",         "PdiffSup",          "PdiffTest",         "PearsonChiSq",
    "PearsonChiSqMC",     "PearsonCorr",               "PearsonCorrMC",       "PearsonCorrTest",   "PlCorr",            "PlCorrTest",
    "QOR",                "RelRisk1ExactCL",           "RelRisk2ExactCL",     "RelativeRiskCLs",   "RelativeRisks",     "RelriskEquiv",
    "RelriskEquivTest",   "RelriskNoninf",             "RelriskSup",          "RelriskTest",       "RiskDiffCol1",      "RiskDiffCol2",
    "RowScores",          "SenSpec",                   "SomersDCR",           "SomersDCRMC",       "SomersDCRTest",     "SomersDRC",
    "SomersDRCMC",        "SomersDRCTest",             "SpearmanCorr",        "SpearmanCorrMC",    "SpearmanCorrTest",  "StratumWeights",
    "SymmetryMC",         "SymmetryTest",              "TauB",                "TauBMC",            "TauBTest",          "TauC",
    "TauCMC",             "TauCTest",                  "TrendTest",           "TrendTestMC",       "WtKappaDetails",    "WtKappaMC",
    "WtKappaTest",
    // UNIVARIATE
           "BasicIntervals",            "BasicMeasures",       "Bins",              "ExtremeObs",        "ExtremeValues",
    "FitQuantiles",       "Frequencies",               "GoodnessOfFit",       "HistogramBins",     "LocationCounts",    "MissingValues",
    "Modes",              "Moments",                   "ParameterEstimates",  "Plots",             "Quantiles",         "RobustScale",
    "SSPlots",            "TestsForLocation",          "TestsForNormality",   "TrimmedMeans",      "WinsorizedMeans",
    // Other procedures
      "Summary",
};

pub fn contains(name: []const u8) bool {
    for (documented) |candidate| if (std.ascii.eqlIgnoreCase(name, candidate)) return true;
    return false;
}

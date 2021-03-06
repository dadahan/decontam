#' Identify contaminant sequences.
#'
#' The frequency of each sequence (or OTU) in the input feature table as a function of the concentration of
#' amplified DNA in each sample is used to identify contaminant sequences.
#'
#' @param seqtab (Required). \code{Integer matrix} or \code{phyloseq} object.
#' A feature table recording the observed abundances of each sequence variant (or OTU) in each sample.
#' Rows should correspond to samples, and columns to sequences (or OTUs).
#' If a phyloseq object is provided, the otu-table component will be extracted.
#'
#' @param conc (Optional). \code{numeric}. Required if performing frequency-based testing.
#' A quantitative measure of the concentration of amplified DNA in each sample prior to sequencing.
#' All values must be greater than zero. Zero is assumed to represent the complete absence of DNA.
#' If \code{seqtab} was prodivded as a phyloseq object, the name of the appropriate sample-variable in that
#' phyloseq object can be provided.
#'
#' @param neg (Optional). \code{logical}. Required if performing prevalence-based testing.
#' TRUE if sample is a negative control, and FALSE if not (NA entries are not included in the testing).
#' Extraction controls give the best results.
#' If \code{seqtab} was provided as a phyloseq object, the name of the appropriate sample-variable in that
#' phyloseq object can be provided.
#'
#' @param method (Optional). \code{character}. The method used to test for contaminants.
#' \describe{
#'   \item{frequency}{Contaminants are identified by increased frequency in lower biomass samples.}
#'   \item{prevalence}{Contaminants are identified by increased prevalence in negative controls.}
#'   \item{combined}{The combined frequency and prevalence p-value (Fisher's method) is used to identify contaminants.}
#'   \item{minimum}{The minimum of the frequency and prevalence p-values is used to identify contaminants.}
#'   \item{independent}{The frequency and prevalence p-values are used independently to identify contaminants.}
#' }
#' If \code{method} is not specified, frequency, prevalence or combined will be automatically selected based on
#' whether just \code{conc}, just \code{neg}, or both were provided.
#'
#' @param batch (Optional). \code{factor}, or any type coercible to a \code{factor}. Default NULL.
#' If provided, should be a vector of length equal to the number of input samples which specifies which batch
#' each sample belongs to (eg. sequencing run). Contaminants identification will be performed independently
#' within each batch.
#' If \code{seqtab} was provided as a phyloseq object, the name of the appropriate sample-variable in that
#' phyloseq object can be provided.
#'
#'
#' @param batch.combine (Optional). Default "minimum".
#' For each input sequence variant (or OTU) the p-values in each batch are combined into a single p-value that is then
#' compared to the `code{threshold}` in order to call contaminants. Valid values: "minimum", "product", "fisher".
#'
#' The "frequency" and "prevalence" p-values are combined across batches independently if both are used.
#'
#' @param threshold (Optional). Default \code{0.1}.
#' The p-value threshold below which (strictly less than) the null-hypothesis (not a contaminant) should be rejected in favor of the
#' alternate hypothesis (contaminant). A length-two vector can be provided when using the independent method:
#' the first value is the threshold for the frequency test and the second for the prevalence test.
#'
#' @param normalize (Optional). Default TRUE.
#' If TRUE, the input \code{seqtab} is normalized so that each row sums to 1 (converted to frequency).
#' If FALSE, no normalization is performed (the data should already be frequencies or counts from equal-depth samples).
#'
#' @param detailed (Optional). Default FALSE.
#' If TRUE, the return value is a \code{data.frame} containing diagnostic information on the contaminant decision.
#' If FALSE, the return value is a \code{logical} vector containing the contaminant decisions.
#'
#' @return
#' If \code{detailed=FALSE} a \code{logical} vector is returned, with TRUE indicating contaminants.
#' If \code{detailed=TRUE} a \code{data.frame} with additional information (such as the p-value) is returned.
#'
#' @importFrom methods as
#' @importFrom methods is
#'
#' @export
#'
#' @examples
#' \dontrun{
#'   isContaminant(st, conc=c(10, 10, 31, 5, 140.1), method="frequency", threshold=0.2)
#'   isContaminant(st, conc=c(10, 10, 31, 5, 140.1), neg=c(TRUE, TRUE, FALSE, TRUE, FALSE), method="minimum", threshold=0.1)
#' }
isContaminant <- function(seqtab, conc=NULL, neg=NULL, method=NULL, batch=NULL, batch.combine="minimum", threshold = 0.1, normalize=TRUE, detailed=FALSE) {
  # Validate input
  if(is(seqtab, "phyloseq")) {
    ps <- seqtab
    seqtab <- as(ps@otu_table, "matrix")
    if(ps@otu_table@taxa_are_rows) { seqtab <- t(seqtab) }
    if(is.character(conc) && length(conc)==1) { conc <- getFromPS(ps, conc) }
    if(is.character(neg) && length(neg)==1) { neg <- getFromPS(ps, neg) }
    if(is.character(batch) && length(batch)==1) { batch <- getFromPS(ps, batch) }
  }
  if(!(is(seqtab, "matrix") && is.numeric(seqtab))) stop("seqtab must be a numeric matrix.")
  if(normalize) seqtab <- sweep(seqtab, 1, rowSums(seqtab), "/")
  if(missing(method)) {
    if(!missing(conc) && missing(neg)) method <- "frequency"
    else if(missing(conc) && !missing(neg)) method <- "prevalence"
    else method <- "combined"
  }
  if(!method %in% c("frequency", "prevalence", "combined", "minimum", "independent")) {
    stop("Valid method arguments: frequency, prevalence, combined, minimum, independent")
  }
  do.freq <- FALSE; do.prev <- FALSE; p.freq <- NA; p.prev <- NA
  if(method %in% c("frequency", "minimum", "combined", "minimum", "independent")) do.freq <- TRUE
  if(method %in% c("prevalence", "combined", "minimum", "independent")) do.prev <- TRUE
  if(do.freq) {
    if(missing(conc)) stop("conc must be provided to perform frequency-based contaminant identification.")
    if(!(is.numeric(conc) && all(conc>0))) stop("conc must be positive numeric.")
    if(nrow(seqtab) != length(conc)) stop("The length of conc must match the number of samples (the rows of seqtab).")
  }
  if(do.prev) {
    if(missing(neg)) stop("neg must be provided to perform prevalence-based contaminant identification.")
  }
  if(is.numeric(threshold) && all(threshold >= 0) && all(threshold <= 1)) {
    if(method == "independent") {
      if(length(threshold) == 1) {
        message("Using same threshold value for the frequency and prevalence contaminant identification.")
        threshold <- c(threshold, threshold)
      }
    } else if(length(threshold) != 1) {
      stop("threshold should be a single value.")
    }
  } else {
    stop("threshold must be a numeric value from 0 to 1 (inclusive).")
  }
  if(missing(batch) || is.null(batch)) {
    batch <- factor(rep(1, nrow(seqtab)))
  }
  if(nrow(seqtab) != length(batch)) stop("The length of batch must match the number of samples (the rows of seqtab).")
  if(!batch.combine %in% c("minimum", "product", "fisher")) stop("Invalid batch.combine value.")
  batch <- factor(batch)
  # Loop over batches
  p.freqs <- matrix(NA, nrow=nlevels(batch), ncol=ncol(seqtab))
  rownames(p.freqs) <- levels(batch)
  p.prevs <- matrix(NA, nrow=nlevels(batch), ncol=ncol(seqtab))
  rownames(p.prevs) <- levels(batch)
  for(bat in levels(batch)) {
    # Calculate frequency p-value
    if(do.freq) {
      p.freqs[bat,] <- apply(seqtab[batch==bat,], 2, isContaminantFrequency, conc=conc[batch==bat])
    }
    # Calculate prevalence p-value
    if(do.prev) {
      p.prevs[bat,] <- apply(seqtab[batch==bat,], 2, isContaminantPrevalence, neg=neg[batch==bat])
    }
  }
  # Combine batch p-values
  if(batch.combine == "minimum") {
    if(do.freq) {
      suppressWarnings(p.freq <- apply(p.freqs, 2, min, na.rm=TRUE))
      p.freq[is.infinite(p.freq)] <- NA # If NA in all batches, min sets to infinite
    }
    if(do.prev) {
      suppressWarnings(p.prev <- apply(p.prevs, 2, min, na.rm=TRUE))
      p.prev[is.infinite(p.prev)] <- NA # If NA in all batches, min sets to infinite
    }
  } else if(batch.combine == "product") {
    if(do.freq) {
      suppressWarnings(p.freq <- apply(p.freqs, 2, prod, na.rm=TRUE))
    }
    if(do.prev) {
      suppressWarnings(p.prev <- apply(p.prevs, 2, prod, na.rm=TRUE))
    }
  } else if(batch.combine == "fisher") {
    if(do.freq) {
      p.freq <- apply(p.freqs, 2, fish.combine, na.replace=0.5)
    }
    if(do.prev) {
      p.prev <- apply(p.prevs, 2, fish.combine, na.replace=0.5)
    }
  } else {
    stop("Invalid batch.combine value.")
  }
  # Calculate overall p-value
  if(method=="frequency") { pval <- p.freq }
  else if(method=="prevalence") { pval <- p.prev }
  else if(method=="minimum") { pval <- pmin(p.freq, p.prev) }
  else if(method=="combined") { pval <- pchisq(-2*log(p.freq * p.prev), df=4, lower.tail=FALSE) }
  else if(method=="independent") { pval <- rep(NA, length(p.freq)) }
  else { stop("Invalid method specified.") }

  if(method=="independent") { # Two tests
    isC <- (p.freq < threshold[[1]]) | (p.prev < threshold[[2]])
  } else { # One test
    isC <- (pval < threshold)
  }
  isC[is.na(isC)] <- FALSE # NA pvals are not called contaminants
  # Make return value
  if(detailed) {
    rval <- data.frame(freq=apply(seqtab,2,mean), prev=apply(seqtab>0,2,sum), p.freq=p.freq, p.prev=p.prev, pval=pval, contaminant=isC)
  } else {
    rval <- isC
  }
  return(rval)
}
#' @importFrom stats lm
#'
#' @keywords internal
isContaminantFrequency <- function(freq, conc) {
  df <- data.frame(logc=log(conc), logf=log(freq))
  df <- df[!is.na(freq) & freq>0,]
  if(nrow(df)>1) {
    lm1 <- lm(logf~offset(-1*logc), data=df)
    SS1 <- sum(lm1$residuals^2)
    lm0 <- lm(logf~1, data=df)
    SS0 <- sum(lm0$residuals^2)
    dof <- sum(freq>0)-1
    pval <- pf(SS1/SS0,dof,dof)
  } else {
    pval <- NA
  }
  return(pval)
}
#' importFrom stats chisq.test
#' importFrom stats fisher.test
#'
#' @export
#'
#' @keywords internal
isContaminantPrevalence <- function(freq, neg, method="auto") {
  fisher.pval <- function(tab, alternative) {
    excess <- fisher.test(tab, alternative="greater")$p.value + fisher.test(tab, alternative="less")$p.value - 1
    pval <- fisher.test(tab, alternative=alternative)$p.value
    pval <- pval - excess/2
    pval
  }
  if(sum(freq>0)>1 && sum(neg,na.rm=TRUE) > 0 && sum(neg,na.rm=TRUE) < sum(!is.na(neg))) {
    tab <- table(factor(neg, levels=c(TRUE, FALSE)), factor(freq>0, levels=c(TRUE, FALSE)))
    # First entry (1,1) is the neg prevalence, so alternative is "greater"
    if((tab[1,2] + tab[2,2]) == 0) { # Present in all samples
      pval <- 0.5
    } else if(method == "fisher") {
      pval <- fisher.pval(tab, alternative="greater")
    } else if(method == "chisq") {
      pval <- prop.test(tab, alternative="greater")$p.value
    } else {
      pval <- tryCatch(prop.test(tab, alternative="greater")$p.value, warning=function(w) fisher.pval(tab, alternative="greater"))
    }
    if(is.na(pval)) {
      warning("NA p-value calculated.")
    }
  } else {
    pval <- NA
  }
  return(pval)
}
# fisher.test(matrix(c(1,10,40,40), nrow=2), alternative="greater")
# contingency table, test is whether the first entry is less than expected under fixed marginals
# so, is there a lower fraction of the first column in row 1 than row 2
# prop.test(matrix(c(1,10,40,40), nrow=2), alternative="greater")
# Same test but using chisq approx, which fails at low numbers
# Warns for low numbers (conditionally use prop.test based on that?)
# tab <- table(factor(df$neg, levels=c(TRUE, FALSE)), factor(df$present, levels=c(TRUE, FALSE)))
# tryCatch(prop.test(tab, alternative="less"), warning=function(w) fisher.test(tab, alternative="less"))

#' Identify non-contaminant sequences.
#'
#' The prevalence of each sequence (or OTU) in the input feature table across samples and negative controls
#' is used to identify non-contaminant sequences. Note that the null hypothesis
#' here is that sequences **are** contaminants. This function is intended for use on low-biomass samples
#' in which a large proportion of the sequences are likely to be contaminants.
#'
#' @param seqtab (Required). Integer matrix.
#' A feature table recording the observed abundances of each sequence (or OTU) in each sample.
#' Rows should correspond to samples, and columns to sequences (or OTUs).
#'
#' @param conc (Optional). \code{numeric}.
#' A quantitative measure of the concentration of amplified DNA in each sample prior to sequencing.
#' All values must be greater than zero. Zero is assumed to represent the complete absence of DNA.
#' REQUIRED if performing frequency-based testing.
#'
#' @param neg (Optional). \code{logical}
#' The negative control samples. Extraction controls give the best results.
#' REQUIRED if performing prevalence-based testing.
#'
#' @param method (Optional). Default "prevalence".
#' The method used to test for contaminants.
#' prevalence: Contaminants are identified by increased prevalence in negative controls.
#'
#' @param threshold (Optional). Default \code{0.5}.
#' The p-value threshold below which (strictly less than) the null-hypothesis (a contaminant) should be rejected in favor of the
#' alternate hypothesis (not a contaminant).
#'
#' @param normalize (Optional). Default TRUE.
#' If TRUE, the input \code{seqtab} is normalized so that each row sums to 1 (converted to frequency).
#' If FALSE, no normalization is performed (the data should already be frequencies or counts from equal-depth samples).
#'
#' @param detailed (Optional). Default FALSE.
#' If TRUE, the return value is a \code{data.frame} containing diagnostic information on the non-contaminant decision.
#' If FALSE, the return value is a \code{logical} vector containing the non-contaminant decisions.
#'
#' @return
#' If \code{detailed=FALSE} a \code{logical} vector is returned, with TRUE indicating non-contaminants.
#' If \code{detailed=TRUE} a \code{data.frame} is returned instead.
#'
#' @export
#'
#' @examples
#' \dontrun{
#'   isNotContaminant(st, conc, threshold=0.05)
#' }
isNotContaminant <- function(seqtab, conc=NULL, neg=NULL, method="prevalence", threshold = 0.5, normalize=TRUE, detailed=FALSE) {
  if(!method %in% c("prevalence")) stop("isNotContaminant only supports the following methods: prevalence")
  df <- isContaminant(seqtab, conc=conc, neg=neg, method=method, threshold=threshold, normalize=normalize, detailed=TRUE)
  df$p.freq <- 1-df$p.freq
  df$p.prev <- 1-df$p.prev
  # Calculate overall p-value
  if(method=="prevalence") { pval <- df$p.prev }
  # Make contaminant calls
  isNotC <- (pval < threshold)
  isNotC[is.na(isNotC)] <- FALSE # NA pvals are not called not-contaminants
  df$pval <- pval
  df$contaminant <- NULL
  df$not.contaminant <- isNotC
  # Make return value
  if(detailed) {
    rval <- df
  } else {
    rval <- isNotC
  }
  return(rval)
}

list_along <- function(nm) {
  if(!is.character(nm)) stop("list_along requires character input.")
  rval <- vector("list", length(nm))
  names(rval) <- nm
}

fish.combine <- function(vec, na.replace=0.5) {
  vec[is.na(vec)] <- na.replace
  if(any(vec<0 | vec>1)) stop("fish.combine expects p-values between 0 and 1.")
  p <- prod(vec)
  pchisq(-2*log(p), df=2*length(vec), lower.tail=FALSE)
}

getFromPS <- function(ps, nm) {
  i <- match(nm, ps@sam_data@names)
  if(is.na(i)) stop(paste(nm, "is not a valid sample-variable in the provided phyloseq object."))
  ps@sam_data@.Data[[i]]
}

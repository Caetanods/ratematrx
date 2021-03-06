% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/plotRootValue.R
\name{plotRootValue}
\alias{plotRootValue}
\title{Plot posterior distribution of root values for the traits}
\usage{
plotRootValue(
  chain,
  color = "black",
  set.xlab = NULL,
  set.cex.lab = 1,
  set.cex.axis = 1.5,
  set.xlim = NULL,
  hpd = 100,
  mfrow = 1,
  vline.values = NULL,
  vline.color = NULL,
  vline.wd = NULL,
  show.zero = FALSE
)
}
\arguments{
\item{chain}{the posterior distribution loaded from the files using 'readMCMC' or samples from the prior generated with the 'samplePrior' function.}

\item{color}{the color for the histograms.}

\item{set.xlab}{a vector with legends for the x axes. If 'NULL' (default), the names are 'trait_1' to 'trait_n".}

\item{set.cex.lab}{the cex value for the labels (default is 1).}

\item{set.cex.axis}{the cex value for the axes numbers (default is 1.5).}

\item{set.xlim}{the xlim for the plot. Need to be a vector with the lower and higher bound.}

\item{hpd}{the Highest Posterior Density interval to highlight in the plot. Parameter values outside this interval will be colored in white. A numeric value between 0 and 100 (default is 100).}

\item{mfrow}{the number of rows to use in the figure (default is 1).}

\item{vline.values}{numeric values for plotting vertical lines. Can be a single value recycled for each of the plots or a vector with length equal to the number of traits.}

\item{vline.color}{character vector with colors for the vertical lines. Can be a single color if length of 'vline.values' is 1 otherwise need to have length equal to the number of traits.}

\item{vline.wd}{numeric value for the width of the vertical lines. Can be a single value if length of 'vline.values' is 1 otherwise need to have length equal to the number of traits.}

\item{show.zero}{whether a vertical line should be plotted showing the position of the value 0 in the plot.}
}
\value{
A plot with the posterior density of root values or distribution of root values sampled from the prior.
}
\description{
Plot the posterior distribution of root values sampled from the MCMC analysis or samples from the prior distribution.
}
\examples{
\donttest{
data( centrarchidae )
dt.range <- t( apply( centrarchidae$data, 2, range ) )
## The step size for the root value can be set given the range we need to sample from:
w_mu <- ( dt.range[,2] - dt.range[,1] ) / 10
par.sd <- cbind(c(0,0), sqrt( c(10,10) ))
prior <- makePrior(r=2, p=2, den.mu="unif", par.mu=dt.range, den.sd="unif", par.sd=par.sd)
prior.samples <- samplePrior(n = 1000, prior = prior)
start.point <- samplePrior(n=1, prior=prior)
## Plot the prior. Red line shows the sample from the prior that will set the starting 
##      point for the MCMC.
plotRatematrix(prior.samples, point.matrix = start.point$matrix, point.color = "red"
               , point.wd = 2)
plotRootValue(prior.samples)
handle <- ratematrixMCMC(data=centrarchidae$data, phy=centrarchidae$phy.map, prior=prior
                         , gen=10000, w_mu=w_mu, dir=tempdir())
posterior <- readMCMC(handle, burn = 0.2, thin = 10)
## Again, here the red line shows the starting point of the MCMC.
plotRatematrix( posterior, point.matrix = start.point$matrix, point.color = "red"
               , point.wd = 2)
plotRootValue(posterior)
}
}
\author{
Daniel S. Caetano and Luke J. Harmon
}

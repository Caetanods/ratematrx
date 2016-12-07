##' Runs a Markov chain Monte Carlo (MCMC) chain to estimate the posterior distribution of two or more
##'    evolutionary rate matrices (R) fitted to the phylogeny.
##'
##' MCMC using the inverse-Wishart as a proposal distribution for the covariance matrix and a simple sliding
##'    window for the phylogenetic mean in the random walk Metropolis-Hastings algorithm. At the moment the
##'    function only applies the 'rpf' method for calculation of the log likelihood implemented in the
##'    package 'mvMORPH'. Future versions should offer different log likelihood methods for the user.
##' This version is using the pruning algoritm to c
##' @title MCMC for two or more evolutionary rate matrices.
##' @param X matrix. A matrix with the data. 'rownames(X) == phy$tip.label'.
##' @param phy simmap phylo. A phylogeny of the class "simmap" from the package 'phytools'. Function uses the location information for a number of traits equal to the number of fitted matrices.
##' @param start list. Element [[1]] is the starting value for the phylogenetic mean and element [[2]] is the starting value for the R matrices. Element [[2]] is also a list with length equal to the number of matrices to be fitted to the data.
##' @param prior list. Produced by the output of the function 'make.prior.barnard' or 'make.prior.diwish'. First element of the list [[1]] is a prior function for the log density of the phylogenetic mean and the second element [[2]] is a prior function for the evolutionary rate matrix (R). The prior can be shared among the rate matrices or be set a different prior for each matrix. At the moment the function only produces a shared prior among the fitted matrices. Future versions will implement independent priors for each of the fitted matrices.
##' @param gen numeric. Number of generations of the MCMC.
##' @param v numeric. Degrees of freedom parameter for the inverse-Wishart proposal distribution for the evolutionary rate matrix.
##' @param w_sd numeric. Width of the uniform sliding window proposal for the vector of standard deviations.
##' @param w_mu numeric. Width of the uniform sliding window proposal for the vector of phylogenetic means. Please note that the proposal can be made for all the traits at the same time or trait by trait. Check the argument "traitwise".
##' @param prop vector. The proposal frequencies. Vector with two elements (each between 0 and 1). First is the probability that the phylogenetic mean will be sampled for a proposal step at each genetarion, second is the probability that the evolutionary rate matrix will be updated instead. First the function sample whether the root value or the matrix should be updated. If the matrix is selected for an update, then one of the matrices fitted to the phylogeny is selected to be updated at random with the same probability.
##' @param chunk numeric. Number of generations that the MCMC chain will be stored in memory before writing to file. At each 'chunk' generations the function will write the block stored in memory to a file and erase all but the last generation, which is used to continue the MCMC chain. Each of the covariance matrices is saved to its own file.
##' @param dir string. Directory to write the files, absolute or relative path. If 'NULL' then output is written to the directory where R is running (see 'getwd()'). If a directory path is given, then function will test if the directory exists and use it. If directiory does not exists the function will try to create one.
##' @param outname string. Name pasted to the files. Name of the output files will start with 'outname'.
##' @param IDlen numeric. Set the length of the unique numeric identifier pasted to the names of all output files. This is set to prevent that multiple runs with the same 'outname' running in the same directory will be lost.Default value of 5 numbers, something between 5 and 10 numbers should be good enough. IDs are generated randomly using the function 'sample'.
##' @param traitwise Whether the proposal for the phylogenetic root is made trait by trait or all the traits at the same time.
##' @param use_corr Whether the proposal for the root value will use the correlation of the tip data to sample proposals following the major axis of variation observed in the data. When this is set to TRUE the update will use a multivariate normal distribution and, thus, will always sample the values for the two traits at once. The value for "traitwise" will be ignored, if "use_corr" is set to TRUE.
##' @return Fuction creates files with the MCMC chain. Each run of the MCMC will be identified by a unique identifier to facilitate identification and prevent the function to overwrite results when running more than one MCMC chain in the same directory. See argument 'IDlen'. The files in the directory are: 'outname.ID.loglik': the log likelihood for each generation, 'outname.ID.n.matrix': the evolutionary rate matrix n, one per line. Function will create one file for each R matrix fitted to the tree, 'outname.ID.root': the root value, one per line. \cr
##' \cr
##' Additionally it returns a list object with information from the analysis to be used by other functions. This list is refered as the 'out' parameter in those functions. The list is composed by: 'acc_ratio' numeric vector with 0 when proposal is rejected and non-zero when proposals are accepted. 1 indicates that root value was accepted, 2 and higher indicates that the first or subsequent matrices were updated; 'run_time' in seconds; 'k' the number of matrices fitted to the tree; 'p' the number of traits in the analysis; 'ID' the identifier of the run; 'dir' directory were output files were saved; 'outname' the name of the chain, appended to the names of the files; 'trait.names' A vector of names of the traits in the same order as the rows of the R matrix, can be used as the argument 'leg' for the plotting function 'make.grid.plot'; 'data' the original data for the tips; 'phy' the phylogeny; 'prior' the list of prior functions; 'start' the list of starting parameters for the MCMC run; 'gen' the number of generations of the MCMC.
##' @export
##' @importFrom geiger treedata
##' @importFrom ape reorder.phylo
##' @importFrom corpcor rebuild.cov
multRegimeMCMC <- function(X, phy, start, prior, gen, v=50, w_sd=0.5, w_mu=0.5, prop=c(0.1,0.9), chunk=gen/100, dir=NULL, outname="mcmc_ratematrix", IDlen=5, traitwise=FALSE, use_corr=FALSE){

    ## Verify the directory:
    if( is.null(dir) ){
        dir <- "."
    } else{
        dir.create(file.path(dir), showWarnings = FALSE)
    }

    ## Change the data to matrix:
    if( class(X) == "data.frame" ) X <- as.matrix( X )

    ## Cache for the data and for the chain:
    cache.data <- list()
    cache.chain <- list()
    
    cache.data$X <- X
    cache.data$data_cor <- cov2cor( var( X ) ) ## This is to use the correlation of the data to draw proposals for the root.
    cache.data$k <- ncol(X) ## Number of traits.

    ## Make the precalculation based on the tree. Here two blocks, depending of whether there is only one or several trees.
    if( is.list(phy[[1]]) ){ ## The problem here is that a 'phylo' is also a list. So this checks if the first element is a list.
        ## All the objects here are of the type list. Need to modify any call to them.
        n.phy <- length( phy ) ## Number of trees in the list.
        cache.chain$which.phy <- vector(mode="integer", length=gen) ## Vector to track which of the phy are we using.
        
        ord.id <- lapply(phy, function(x) reorder.phylo(x, order="postorder", index.only = TRUE) ) ## Order for traversal.
        cache.data$mapped.edge <- lapply(1:n.phy, function(x) phy[[x]]$mapped.edge[ord.id[[x]],]) ## The regimes.
        anc <- lapply(1:n.phy, function(x) phy[[x]]$edge[ord.id[[x]],1] ) ## Ancestral edges.
        cache.data$des <- lapply(1:n.phy, function(x) phy[[x]]$edge[ord.id[[x]],2] ) ## Descendent edges.
        cache.data$nodes <- lapply(anc, unique) ## The internal nodes we will traverse.

        ## Set the types for each of the nodes that are going to be visited.
        node.to.tip <- lapply(1:n.phy, function(x) which( tabulate( anc[[x]][which(cache.data$des[[x]] <= length(phy[[x]]$tip.label))] ) == 2 ) )
        node.to.node <- lapply(1:n.phy, function(x) which( tabulate( anc[[x]][which(cache.data$des[[x]] > length(phy[[x]]$tip.label))] ) == 2 ) )
        node.to.tip.node <- lapply(1:n.phy, function(x) unique( anc[[x]] )[!unique( anc[[x]] ) %in% c(node.to.node[[x]], node.to.tip[[x]])] )
        ## 1) nodes to tips: nodes that lead only to tips, 2) nodes to nodes: nodes that lead only to nodes, 3) nodes to tips and nodes: nodes that lead to both nodes and tips.
        for( i in 1:n.phy ){
            names(anc[[i]]) <- rep(1, times=length(anc[[i]]))
            names(anc[[i]])[which(anc[[i]] %in% node.to.node[[i]])] <- 2
            names(anc[[i]])[which(anc[[i]] %in% node.to.tip.node[[i]])] <- 3
        }
        cache.data$anc <- anc ## This need to come with the names.
    }
    if( !is.list(phy[[1]]) ){ ## There is only one phylogeny.
        cache.chain$which.phy <- NULL ## To inform that only one tree was used in the MCMC.
        
        ord.id <- reorder.phylo(phy, order="postorder", index.only = TRUE) ## Order for traversal.
        cache.data$mapped.edge <- phy$mapped.edge[ord.id,] ## The regimes.
        ## Need to take care how to match the regimes and the R matrices.
        anc <- phy$edge[ord.id,1] ## Ancestral edges.
        cache.data$des <- phy$edge[ord.id,2] ## Descendent edges.
        cache.data$nodes <- unique(anc) ## The internal nodes we will traverse.

        ## Set the types for each of the nodes that are going to be visited.
        node.to.tip <- which( tabulate( anc[which(cache.data$des <= length(phy$tip.label))] ) == 2 )
        node.to.node <- which( tabulate( anc[which(cache.data$des > length(phy$tip.label))] ) == 2 )
        node.to.tip.node <- unique( anc )[!unique( anc ) %in% c(node.to.node, node.to.tip)]
        ## 1) nodes to tips: nodes that lead only to tips, 2) nodes to nodes: nodes that lead only to nodes, 3) nodes to tips and nodes: nodes that lead to both nodes and tips.
        names(anc) <- rep(1, times=length(anc))
        names(anc)[which(anc %in% node.to.node)] <- 2
        names(anc)[which(anc %in% node.to.tip.node)] <- 3
        cache.data$anc <- anc ## This need to come with the names.
    }
    
    cache.data$p <- length( start[[2]] ) ## Number of R matrices to be fitted. Do I need this?

    ## Creates MCMC chain cache:
    cache.chain$chain <- vector(mode="list", length=chunk+1) ## Chain list.
    cache.chain$chain[[1]] <- start ## Starting value for the chain.
    cache.chain$chain[[1]][[4]] <- list()
    for(i in 1:cache.data$p) cache.chain$chain[[1]][[4]][[i]] <- rebuild.cov(r=cov2cor(start[[2]][[i]]), v=start[[3]][[i]]^2)
    cache.chain$acc <- vector(mode="integer", length=gen) ## Vector for acceptance ratio.
    cache.chain$acc[1] <- 1 ## Represents the starting value.
    ## Create column vector format for start state of b (phylo mean).
    ##cache.chain$b.curr <- matrix( sapply(as.vector(cache.chain$chain[[1]][[1]]), function(x) rep(x, cache.data$n) ) )
    cache.chain$lik <- vector(mode="numeric", length=chunk+1) ## Lik vector.

    ## Need to calculate the initial log.lik with the single tree or with a random tree from the sample:
    if( is.list( phy[[1]] ) ){
        rd.start.tree <- sample(1:n.phy, size = 1)
        cache.chain$which.phy[1] <- rd.start.tree ## The index for the starting likelihood.
        cache.chain$lik[1] <- logLikPrunningMCMC(cache.data$X, cache.data$k, cache.data$nodes[[rd.start.tree]], cache.data$des[[rd.start.tree]]
                                       , cache.data$anc[[rd.start.tree]], cache.data$mapped.edge[[rd.start.tree]]
                                       , R=cache.chain$chain[[1]][[2]], mu=as.vector(cache.chain$chain[[1]][[1]]) )
    }
    if( !is.list( phy[[1]] ) ){
        cache.chain$lik[1] <- logLikPrunningMCMC(cache.data$X, cache.data$k, cache.data$nodes, cache.data$des, cache.data$anc, cache.data$mapped.edge
                                       , R=cache.chain$chain[[1]][[2]], mu=as.vector(cache.chain$chain[[1]][[1]]) )
    }
    cache.chain$curr.root.prior <- prior[[1]](cache.chain$chain[[1]][[1]]) ## Prior log lik starting value.
    ## Prior log lik starting value for each of the matrices.
    ## cache.chain$curr.r.prior <- lapply(1:cache.data$p, function(x) prior[[2]](cache.chain$chain[[1]][[2]][[x]]) )
    cache.chain$curr.r.prior <- prior[[2]](cache.chain$chain[[1]][[4]]) ## Takes a list of R and returns a numeric.

    ## Will need to keep track of the Jacobian for the correlation matrix.
    decom <- lapply(1:cache.data$p, function(x) decompose.cov( cache.chain$chain[[1]][[2]][[x]] ) )
    cache.chain$curr.r.jacobian <- lapply(1:cache.data$p,
                                          function(y) sum( sapply(1:cache.data$k, function(x) log( decom[[y]]$v[x]) ) ) * log( (cache.data$k-1)/2 ) )
    
    ## cache.chain$curr.sd.prior <- lapply(1:cache.data$p, function(x) prior[[3]](cache.chain$chain[[1]][[3]][[x]]) ) ## Prior log lik starting value.
    cache.chain$curr.sd.prior <- prior[[3]](cache.chain$chain[[1]][[3]]) ## Takes a list of sd vectors and returns a numeric.
    
    ## Generate identifier:
    ID <- paste( sample(x=1:9, size=IDlen, replace=TRUE), collapse="")

    ## Open files to write:
    ## Need to open one matrix file per p R matrices to be fitted.
    ## Different from the single.R case. These lists have no names.
    files <- list( file(file.path(dir, paste(outname,".",ID,".loglik",sep="")), open="a"),
                   file(file.path(dir, paste(outname,".",ID,".root",sep="")), open="a")
                 )
    for(i in 3:(cache.data$p+2)){
        files[[i]] <- file(file.path(dir, paste(outname,".",ID,".",(i-2),".matrix",sep="")),open="a")
    }

    ## This will check for the arguments, check if there is more than one phylogeny and create the functions for the update and to calculate the lik.
    if( !is.list( phy[[1]] ) ){
        ## This will use a unique tree.
        print("MCMC chain will use a single tree provided in the argument 'phy'")
        if(use_corr == TRUE){
            print("Using a data informed joint proposal distribution for the phylogenetic mean, value of 'traitwise' ignored.")
            prop.data.cor <- function(...) makePropMeanForMult(..., traitwise=FALSE, use_corr=TRUE)
            update.function <- list(prop.data.cor, makePropMultSigma)
        } else{
            if(traitwise == TRUE){
                print("Using an independent proposal distribution for the root value of each trait.")
                prop.traitwise <- function(...) makePropMeanForMult(..., traitwise=TRUE, use_corr=FALSE)
                update.function <- list(prop.traitwise, makePropMultSigma)
            }
            if(traitwise == FALSE){
                print("Using a naive joint proposal distribution for the phylogenetic mean.")
                prop.not.traitwise <- function(...) makePropMeanForMult(..., traitwise=FALSE, use_corr=FALSE)
                update.function <- list(prop.not.traitwise, makePropMultSigma)
            }

        }
    }
    if( is.list( phy[[1]] ) ){
        print("MCMC chain will integrate over the list of phylogenies provided in the argument 'phy'")
        ## This will integrate over all the trees provided.
        if(use_corr == TRUE){
            print("Using a data informed joint proposal distribution for the phylogenetic mean, value of 'traitwise' ignored.")
            prop.data.cor <- function(...) makePropMeanForMultList(..., n.phy=n.phy, traitwise=FALSE, use_corr=TRUE)
            update.function <- list(prop.data.cor, function(...) makePropMultSigmaList(..., n.phy=n.phy) )
        } else{
            if(traitwise == TRUE){
                print("Using an independent proposal distribution for the root value of each trait.")
                prop.traitwise <- function(...) makePropMeanForMultList(..., n.phy=n.phy, traitwise=TRUE, use_corr=FALSE)
                update.function <- list(prop.traitwise, function(...) makePropMultSigmaList(..., n.phy=n.phy) )
            }
            if(traitwise == FALSE){
                print("Using a naive joint proposal distribution for the phylogenetic mean.")
                prop.not.traitwise <- function(...) makePropMeanForMultList(..., n.phy=n.phy, traitwise=FALSE, use_corr=FALSE)
                update.function <- list(prop.not.traitwise, function(...) makePropMultSigmaList(..., n.phy=n.phy) )
            }

        }
    }

    ## Calculate chunks and create write point.
    block <- gen/chunk

    ## Start counter for the acceptance ratio and loglik.
    count <- 2

    ## Save a log file with the accept and reject information:
    sink( file.path(dir, paste(outname,".",ID,".mcmc.log", sep="") ) )

    ## Make loop equal to the number of blocks:
    for(jj in 1:block){

        ## Loop over the generations in each chunk:
        for(i in 2:(chunk+1) ){

            ## Proposals will be sampled given the 'prop' vector of probabilities.

            ###########################################
            ## Sample which parameter is updated:
            ## 'prop' is a vector of probabilities for 'update.function' 1 or 2.
            ## 1 = phylo root and 2 = R matrix.
            up <- sample(x = c(1,2), size = 1, prob = prop)
            ###########################################

            ###########################################
            ## Update and accept reject steps:
            ## Did a small modification to the prop of the phylogenetic mean that now requires the function to be called with its explicit argnames.
            cache.chain <- update.function[[up]](cache.data=cache.data, cache.chain=cache.chain, prior=prior, v=v, w_sd=w_sd, w_mu=w_mu, iter=i, count=count)
            ## Update counter.
            count <- count+1
            ###########################################
            
        }
        
        ###########################################
        ## Write to file:
        ## This version will have one file for each of the p R matrices.
        cache.chain <- writeToMultFile(files, cache.chain, p=cache.data$p, chunk)
        ###########################################
        
    }

    ## Close the connection to the log:
    sink()

    ## Stops the clock.
    ## time <- proc.time() - ptm

    ## Close the connections:
    lapply(files, close)

    ## Create table of acceptance ratio.
    ## acc.mat <- matrix(table(cache.chain$acc), nrow=1)
    ## colnames(acc.mat) <- c("reject","root",paste("R", 1:cache.data$p, sep=""))

    ## Returns 'p = 1' to indentify the results as a single R matrix fitted to the data.
    ## Returns the data, phylogeny, priors and start point to work with other functions.
    out <- list(acc_vector = cache.chain$acc, which.phy = cache.chain$which.phy, k = cache.data$k, p = cache.data$p
               , ID = ID, dir = dir, outname = outname, trait.names = cache.data$traits, data = X
               , phy = phy, prior = prior, start = start, gen = gen)
    class( out ) <- "ratematrix_multi_mcmc"
    return( out )
}
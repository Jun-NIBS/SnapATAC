#' @include snap-class.R
NULL
#' K Nearest Neighbour Graph Construction
#'
#' Constructs a K Nearest Neighbor (SNN) Graph from a snap object. 
#' The k-nearest neighbors of each cell were identified and used to create
#' a KNN graph. 
#' 
#' Using the selected significant principal components (PCs), we next calculated pairwise 
#' Euclidean distance between every two cells, using this distance, we created a k-nearest 
#' neighbor graph in which every cell is represented as a node and edges are drawn between 
#' cells within k nearest neighbors. Edge weight between any two cells can be refined by shared 
#' overlap in their local neighborhoods using Jaccard similarity (snn).
#'
#' @param obj A snap object
#' @param pca.dims A vector of the dimensions to use in construction of the KNN graph.
#' @param weight.by.sd Weight the cell embeddings by the sd of each PC
#' @param k K for the k-nearest neighbor algorithm.
#' @param nn.eps Error bound when performing nearest neighbor seach using RANN.
#' default of 0.0 implies exact nearest neighbor search
#' @param save.knn Default is to store the KNN in object@@kmat. Setting
#' to FALSE can be used together with a provided filename to only write the KNN
#' out as an edge file to disk. This is compatible with runCluster.
#' @param filename Write KNN directly to file named here as an edge list
#' compatible with runCluster.
#' @param snn Setting to TRUE can convert KNN graph into a SNN graph.
#' @param snn.prune Sets the cutoff for acceptable Jaccard index when
#' computing the neighborhood overlap. Any edges with values less than or 
#' equal to this will be set to 0 and removed from the SNN graph. Essentially 
#' sets the strigency of pruning (0 --- no pruning, 1 --- prune everything).
#' 
#' @examples
#' data(demo.sp);
#' demo.sp = runKNN(obj=demo.sp, pca.dims=1:5, k=15, snn=TRUE, save.knn=FALSE);
#' 
#' @importFrom RANN nn2
#' @importFrom igraph similarity graph_from_edgelist E
#' @importFrom Matrix sparseMatrix
#' @importFrom plyr count
#' @importFrom methods as
#' @import Matrix
#' @return Returns the object with object@kmat filled
#' @export

runKNN <- function(obj, pca.dims, weight.by.sd, k, nn.eps, save.knn, filename, snn, snn.prune) {
  UseMethod("runKNN", obj);
}

#' @export
runKNN.default <- function(
  obj,
  pca.dims,
  weight.by.sd = FALSE,
  k = 15,
  nn.eps = 0,
  save.knn = FALSE,
  filename = NULL,
  snn = FALSE,
  snn.prune = 1/15
){
	cat("Epoch: checking input parameters\n", file = stderr())
	if(missing(obj)){
		stop("obj is missing")
	}else{
		if(!is(obj, "snap")){
			stop("obj is not a snap obj")
		}
	}
	
	if(!(isDimReductComplete(obj@smat))){
		stop("dimentionality reduction is not complete, run 'runDimReduct' first")
	}
	
	ncell = nrow(obj);
	nvar = dimReductDim(obj@smat);
	
	if(missing(pca.dims)){
		stop("pca.dims is missing")
	}else{
		if(is.null(pca.dims)){
			pca.dims=1:nvar;	
		}else{
			if(any(pca.dims > nvar) ){
				stop("'pca.dims' exceeds PCA dimentions number");
			}		
		}
	}
	
	if(save.knn){
		if(is.null(filename)){
			stop("save.knn is TRUE but filename is NULL")
		}else{			
			if(!file.create(filename)){
				stop("fail to create filename")
			}			
		}
	}
	
	if(!is.logical(weight.by.sd)){
		stop("weight.by.sd must be a logical variable")
	}
	
	data.use = weightDimReduct(obj@smat, pca.dims, weight.by.sd);
	
    if (ncell < k) {
      warning("k set larger than number of cells. Setting k to number of cells - 1.")
      k <- ncell - 1
    }
	
	if(is.na(as.integer(k))){
		stop("k must be an integer")
	}else{
		if(k < 10 || k > 50){
			warning("too small or too large k, recommend to set k within range [10 - 50]")
		}
	}
	
	cat("Epoch: computing nearest neighbor graph\n", file = stderr())
	
    nn.ranked <- nn2(
        data = data.use,
        k = k+1,
        searchtype = 'standard',
        eps = nn.eps)$nn.idx;

	# exclude self neibours
	nn.ranked = nn.ranked[,2:(k+1)];	
	edgeList <- t(matrix(unlist(sapply(1:ncell,function(i) { rbind(rep(i,k),nn.ranked[i,])})),nrow=2));
	edgeList.1 <- edgeList[which(edgeList[,1] <= edgeList[,2]),]
	edgeList.2 <- edgeList[which(edgeList[,1] > edgeList[,2]),]	
	edgeList.2 <- cbind(edgeList.2[,2], edgeList.2[,1])
	edgeList = rbind(edgeList.1, edgeList.2);
	edgeList <- data.frame(v1=edgeList[,1], v2=edgeList[,2]);
	edgeList = count(edgeList, vars = c("v1", "v2"));
	
	if(snn){
		cat("Epoch: converting knn graph into snn graph\n", file = stderr())		
		g = graph_from_edgelist(as.matrix(edgeList[,c(1,2)]), directed=FALSE);
		igraph::E(g)$weight = edgeList[,3];
		adj = as(similarity(g), "sparseMatrix");
		i = adj@i+1;
		j = findInterval(seq(adj@x)-1,adj@p[-1])+1;
		w = adj@x;
		idx = which(w >= snn.prune);
		edgeList = data.frame(i[idx], j[idx], w[idx]);
	}
	
	if(save.knn){
		cat("Epoch: writing resulting graph into a file\n", file = stderr())
		writeEdgeListToFile(edgeList, filename);
		obj@graph = newKgraph(file=filename, k=k, snn=snn, snn.prune=snn.prune);
	}else{
		kmat = Matrix(0, ncell, ncell, sparse=TRUE);
		kmat[cbind(edgeList[,1], edgeList[,2])] = edgeList[,3]
		kmat[cbind(edgeList[,2], edgeList[,1])] = edgeList[,3]
		obj@graph = newKgraph(mat=kmat, k=k, snn=snn, snn.prune=snn.prune);
	}
	gc();
	return(obj);
} 






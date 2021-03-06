################################################################################
#
#      Migratory Connectivity Metric - Cohen et al.
#
#      Geolocator data and GPS data from OVENBIRDS
#      Geolocator data - Hallworth et al. 2015 - Ecological Applications
#      GPS data - Hallworth and Marra 2015 Scientific Reports
#
#      Script written by M.T.Hallworth & J.A.Hostetler
################################################################################
# load required packages

library(raster)
library(sp)
library(rgeos)
library(rgdal)
library(SpatialTools)
library(geosphere)
library(maptools)
library(shape)
library(ade4)

###################################################################
#
# geoVcov & geoBias
#
###################################################################

WGS84<-"+proj=longlat +datum=WGS84 +no_defs +ellps=WGS84 +towgs84=0,0,0"
Lambert<-"+proj=aea +lat_1=20 +lat_2=60 +lat_0=40 +lon_0=-96 +x_0=0 +y_0=0 +ellps=GRS80 +datum=NAD83 +units=m +no_defs"
EquidistConic <- "+proj=eqc +lat_ts=0 +lat_0=0 +lon_0=0 +x_0=0 +y_0=0 +a=6371007 +b=6371007 +units=m +no_defs"

# Define capture locations in the winter #

captureLocations<-matrix(c(-77.93,18.04,  # Jamaica
                           -80.94,25.13,  # Florida
                           -66.86,17.97,  # Puerto Rico
                           -71.72,43.95), # New Hampshire
                          nrow=4,ncol=2,byrow=TRUE)

# Convert capture locations into SpatialPoints #

CapLocs<-SpatialPoints(captureLocations,CRS(WGS84))

# Project Capture locations #

CapLocsM<-spTransform(CapLocs, CRS(EquidistConic))

# Retrieve raw non-breeding locations from github #
# First grab the identity of the bird so we can loop through the files #
# For this example we are only interested in the error around non-breeding locations #
# here we grab only the birds captured during the non-breeding season #

winterBirds <- dget("https://raw.githubusercontent.com/SMBC-NZP/MigConnectivity/master/data-raw/GL_NonBreedingFiles/winterBirds.txt")

# create empty list to store the location data #
Non_breeding_files <- vector('list',length(winterBirds))

# Get raw location data from Github #
for(i in 1:length(winterBirds)){
  Non_breeding_files[[i]] <- dget(paste0("https://raw.githubusercontent.com/SMBC-NZP/MigConnectivity/master/data-raw/GL_NonBreedingFiles/NonBreeding_",winterBirds[i],".txt"))
}

# Remove locations around spring Equinox and potential migration points - same NB time frame as Hallworth et al. 2015 #
# two steps because subset on shapefile doesn't like it in a single step

Non_breeding_files <- lapply(Non_breeding_files,FUN = function(x){month <- as.numeric(format(x$Date,format = "%m"))
x[which(month != 3 & month != 4),]})


Jam <- c(1:9)   # locations within the list of winterBirds captured in Jamaica
Fla <- c(10:12) # locations within the list of winterBirds in Florida
PR <- c(13:16)  # locations within the list of winterBirds in Puerto Rico

# Turn the locations into shapefiles #

NB_GL <- lapply(Non_breeding_files, FUN = function(x){sp::SpatialPoints(cbind(x$Longitude,x$Latitude),CRS(WGS84))})

# Project into UTM projection #

NB_GLmeters <- lapply(NB_GL, FUN = function(x){sp::spTransform(x,CRS(EquidistConic))})

# Process to determine geolocator bias and variance-covariance in meters #

# generate empty vector to store data #
LongError<-rep(NA,length(winterBirds)) # 16 birds were recovered during the non-breeding season
LatError<-rep(NA,length(winterBirds))

# Calculate the error in longitude derived from geolocators from the true capture location #
LongError[Jam] <- unlist(lapply(NB_GLmeters[Jam],FUN = function(x){mean(x@coords[,1]-CapLocsM@coords[1,1])}))
LongError[Fla] <- unlist(lapply(NB_GLmeters[Fla],FUN = function(x){mean(x@coords[,1]-CapLocsM@coords[2,1])}))
LongError[PR] <- unlist(lapply(NB_GLmeters[PR],FUN = function(x){mean(x@coords[,1]-CapLocsM@coords[3,1])}))

# Calculate the error in latitude derived from geolocators from the true capture location #
LatError[Jam] <- unlist(lapply(NB_GLmeters[Jam],FUN = function(x){mean(x@coords[,2]-CapLocsM@coords[1,2])}))
LatError[Fla] <- unlist(lapply(NB_GLmeters[Fla],FUN = function(x){mean(x@coords[,2]-CapLocsM@coords[2,2])}))
LatError[PR] <- unlist(lapply(NB_GLmeters[PR],FUN = function(x){mean(x@coords[,2]-CapLocsM@coords[3,2])}))


# Get co-variance matrix for error of known non-breeding deployment sites #

geo.error.model <- lm(cbind(LongError,LatError) ~ 1) # lm does multivariate normal models if you give it a matrix dependent variable!

geo.bias <- coef(geo.error.model)
geo.vcov <- vcov(geo.error.model)

###################################################################
#
#   Winter Locations - targetPoints
#     length = n animals tracked
#
###################################################################

#########################################################################################
#
# Here instead of using the raw points - use the KDE to estimate location mean locations
#
#########################################################################################
# Non-breeding #

NB_KDE_names<-list.files("data-raw/NonBreeding_Clipped_KDE", pattern="*_clip.txt",full.names=TRUE)

NB_KDE<-lapply(NB_KDE_names,raster)

nGL <- length(NB_KDE_names)

# Get weighted means from KDE #
kdelist<-vector('list',nGL)
NB_kde_long<-NB_kde_lat<-rep(NA,nGL)

for(i in 1:nGL){
kdelist[[i]]<-rasterToPoints(NB_KDE[[i]])
NB_kde_long[i]<-weighted.mean(x=kdelist[[i]][,1],w=kdelist[[i]][,3])
NB_kde_lat[i]<-weighted.mean(x=kdelist[[i]][,2],w=kdelist[[i]][,3])
}

# Replace estimated locations with TRUE capture locations - Jam, Fla, PR birds #
NB_kde_long[c(1,9,21,22,24,25,29,31,36)]<--77.94 # Jamaica
NB_kde_lat[c(1,9,21,22,24,25,29,31,36)]<-18.04 # Jamaica

NB_kde_long[c(17,18,23)]<--80.94 # FLA
NB_kde_lat[c(17,18,23)]<-25.13 # FLA

NB_kde_long[c(32,33,34,35)]<--66.86 # PR
NB_kde_lat[c(32,33,34,35)]<-17.97 # PR

weightedNB<-SpatialPoints(as.matrix(cbind(NB_kde_long,NB_kde_lat)))
crs(weightedNB)<-WGS84
weightedNBm<-spTransform(weightedNB,CRS(EquidistConic))

# USE ONLY BIRDS CAPTURED DURING BREEDING SEASON - GEOLOCATORS #
summerDeploy<-c(2,3,4,5,6,7,8,10,11,12,13,14,15,16,19,20,26,27,28,30)
nB_GL <- length(summerDeploy)

#######################################################################################################################################################
#
# Add the GPS data into the mix
#
#######################################################################################################################################################
GPSdata<-read.csv("data-raw/Ovenbird_GPS_HallworthMT_FirstLast.csv")
nGPS <- nrow(GPSdata)/2
GPSpts<-SpatialPoints(as.matrix(cbind(GPSdata[,2],GPSdata[,1]),nrow=nGPS,ncol=2,byrow=TRUE),CRS(WGS84))
GPSptsm<-spTransform(GPSpts,CRS(EquidistConic))

# First add GPS locations to both breeding and non-breeding data sets #
cap<-seq(1,2*nGPS,2)
wint<-seq(2,2*nGPS,2)

# Using the weighted locations #

weightedNB_breeDeployOnly<-SpatialPoints(as.matrix(cbind(c(NB_kde_long[summerDeploy],GPSdata[wint,2]),c(NB_kde_lat[summerDeploy],GPSdata[wint,1]))))
crs(weightedNB_breeDeployOnly)<-WGS84
NB_breedDeploy<-spTransform(weightedNB_breeDeployOnly,CRS(EquidistConic))

isGL<-c(rep(TRUE,20),rep(FALSE,19))
targetPoints<-NB_breedDeploy


###################################################################
#
#  Capture Locations - OriginPoints
#     length = n animals tracked
#
###################################################################


Origin<-SpatialPoints(cbind(c(rep(captureLocations[4,1],20),GPSdata[cap,2]),c(rep(captureLocations[4,2],20),GPSdata[cap,1])))
crs(Origin)<-WGS84

originPoints<-spTransform(Origin,CRS(EquidistConic))

###################################################################
#
#  Origin & Target sites
#
###################################################################
World<-shapefile("data-raw/Spatial_Layers/TM_WORLD_BORDERS-0.3.shp")
World<-spTransform(World,CRS(EquidistConic))
States<-shapefile("data-raw/Spatial_Layers/st99_d00.shp")
States<-spTransform(States,CRS(EquidistConic))

# Non-breeding - Target sites #
Florida<-subset(States,subset=NAME=="Florida")
Florida<-gUnaryUnion(Florida)
Cuba<-subset(World,subset=NAME=="Cuba")
Hisp<-gUnion(subset(World,subset=NAME=="Haiti"),subset(World,subset=NAME=="Dominican Republic"))

# Change IDs to merge files together
Cuba<-spChFIDs(Cuba,"Cuba")
Florida<-spChFIDs(Florida,"Florida")
Hisp<-spChFIDs(Hisp,"Hisp")

#Combine into a single SpatialPolygon
WinterRegion1 <- spRbind(Florida,Cuba)
WinterRegions<-spRbind(WinterRegion1,Hisp)

targetSites<-WinterRegions

# Make polygons -
# Breeding - Make square region around capture location - equal size around NH and MD.

# Polygon around MD #
mdvertx<-c((1569680-(536837/2)),(1569680-(536837/2)),(1569680+(536837/2)),(1569680+(536837/2)))
mdverty<-c(-212648,324189,324189,-212648)
mdp<-Polygon(cbind(mdvertx,mdverty))
MDbreedPoly<-SpatialPolygons(list(Polygons(list(mdp),ID=1)))

# Polygon around NH #
nhvertx<-c((1810737-(536837/2)),(1810737-(536837/2)),(1810737+(536837/2)),(1810737+(536837/2)))
nhverty<-c(324189,861026,861026,324189)
nhbp<-Polygon(cbind(nhvertx,nhverty))
NHbreedPoly<-SpatialPolygons(list(Polygons(list(nhbp),ID=1)))

NHbreedPoly<-spChFIDs(NHbreedPoly,"NH")
MDbreedPoly<-spChFIDs(MDbreedPoly,"MD")

crs(NHbreedPoly) <- crs(MDbreedPoly) <- Lambert

originSites<-spRbind(NHbreedPoly,MDbreedPoly)
crs(originSites)<-Lambert

originSites <- spTransform(originSites,CRS(EquidistConic))

###################################################################
#
#  Get relative abundance within breeding "population" polygons #
#
###################################################################

# Breeding Bird Survey Abundance Data #
BBSoven<-raster("data-raw/Spatial_Layers/bbsoven.txt")
crs(BBSoven)<-WGS84
BBSovenMeters<-projectRaster(BBSoven,crs=EquidistConic)

NHbreedPoly <- spTransform(NHbreedPoly,CRS(EquidistConic))
MDbreedPoly <- spTransform(MDbreedPoly,CRS(EquidistConic))

NHabund<-extract(BBSovenMeters,NHbreedPoly)
MDabund<-extract(BBSovenMeters,MDbreedPoly)
TotalOvenAbund<-sum(NHabund[[1]],na.rm=TRUE)+sum(MDabund[[1]],na.rm=TRUE)


BreedRelAbund<-array(NA,c(2,1))
BreedRelAbund[1,1]<-sum(NHabund[[1]],na.rm=TRUE)/TotalOvenAbund
BreedRelAbund[2,1]<-sum(MDabund[[1]],na.rm=TRUE)/TotalOvenAbund

originRelAbund<-BreedRelAbund

###################################################################
#
#  Generate Distance matrices
#
###################################################################
# First need to project from meters to Lat/Long -WGS84
# define current projection #

# project to WGS84
NHbreedPolyWGS<-spTransform(NHbreedPoly,CRS(WGS84))
MDbreedPolyWGS<-spTransform(MDbreedPoly,CRS(WGS84))

BreedDistMat<-array(NA,c(2,2))
rownames(BreedDistMat)<-colnames(BreedDistMat)<-c(1,2)
diag(BreedDistMat)<-0
BreedDistMat[1,2]<-BreedDistMat[2,1]<-distVincentyEllipsoid(gCentroid(MDbreedPolyWGS, byid=TRUE, id = MDbreedPolyWGS@polygons[[1]]@ID)@coords,
                                                         gCentroid(NHbreedPolyWGS, byid=TRUE, id = NHbreedPolyWGS@polygons[[1]]@ID)@coords)


# Project to WGS84 #
FloridaWGS<-spTransform(Florida,CRS(WGS84))
CubaWGS<-spTransform(Cuba,CRS(WGS84))
HispWGS<-spTransform(Hisp,CRS(WGS84))


NBreedDistMat<-array(NA,c(3,3))
rownames(NBreedDistMat)<-colnames(NBreedDistMat)<-c(3,4,5)

diag(NBreedDistMat)<-0
NBreedDistMat[2,1]<-NBreedDistMat[1,2]<-distVincentyEllipsoid(gCentroid(FloridaWGS, byid=FALSE)@coords,
                                                           gCentroid(CubaWGS, byid=FALSE)@coords)
NBreedDistMat[3,1]<-NBreedDistMat[1,3]<-distVincentyEllipsoid(gCentroid(FloridaWGS, byid=FALSE)@coords,
                                                           gCentroid(HispWGS, byid=FALSE)@coords)
NBreedDistMat[3,2]<-NBreedDistMat[2,3]<-distVincentyEllipsoid(gCentroid(CubaWGS, byid=FALSE)@coords,
                                                         gCentroid(HispWGS, byid=FALSE)@coords)


originDist<-BreedDistMat
targetDist<-NBreedDistMat

###################################################################
#
#  Write required data to the data folder
#
###################################################################

# Put all components of the OVEN Geolocator and GPS data into a named list
OVENdata<-vector('list',10)
names(OVENdata)<-c("geo.bias","geo.vcov","isGL","targetPoints","originPoints",
                   "targetSites","originSites","originRelAbund","originDist","targetDist")

OVENdata[[1]]<-geo.bias
OVENdata[[2]]<-geo.vcov
OVENdata[[3]]<-isGL
OVENdata[[4]]<-targetPoints
OVENdata[[5]]<-originPoints
OVENdata[[6]]<-targetSites
OVENdata[[7]]<-originSites
OVENdata[[8]]<-originRelAbund
OVENdata[[9]]<-originDist
OVENdata[[10]]<-targetDist

# Save to data folder
devtools::use_data(OVENdata, overwrite = T)






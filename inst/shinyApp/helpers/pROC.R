#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# Roc Parcial
# A little modification of the funcion of Narayani Barve
# ENMGadgets package
# https://github.com/narayanibarve/ENMGadgets
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

PartialROC <- function(PresenceFile=NA, PredictionFile=NA, OmissionVal=NA, RandomPercent=NA, NoOfIteration=NA)
{

  InRast = raster(PredictionFile)
  ## Currently fixing the number of classes to 100. But later flexibility should be given in the parameter.
  InRast = round(InRast * 100)

  ## This function should be called only once outside the loop. This function generates values for x-axis.
  ## As x-axis is not going to change.
  ClassPixels = AreaPredictedPresence(InRast)

  Occur = read.table(PresenceFile, header=T, sep =",")
  Occur = Occur[,-1]
  ExtRast = extract(InRast, Occur)


  ## Remove all the occurrences in the class NA. As these points are not used in the calibration.
  OccurTbl = cbind(Occur, ExtRast)
  OccurTbl = OccurTbl[which(is.na(OccurTbl[,3]) == FALSE),]

  PointID = seq(1:nrow(OccurTbl))
  OccurTbl = cbind(PointID, OccurTbl)
  names(OccurTbl)= c("PointID", "Longitude", "Latitude", "ClassID")
  # # ## Generate the % points within each class in this table. Write SQL, using sqldf package
  # # OccurINClass = sqldf("Select count(*), ClassID from OccurTbl group by ClassID order by ClassID desc")
  # # OccurINClass = cbind(OccurINClass, cumsum(OccurINClass[,1]), cumsum(OccurINClass[,1]) / nrow(OccurTbl))
  # # names(OccurINClass) = c("OccuCount", "ClassID", "OccuSumBelow", "Percent")

  ## Use option cl.cores to choose an appropriate cluster size.

  lapply(X = 1:NoOfIteration,FUN =  function(x){
    ll = sample(nrow(OccurTbl), round(RandomPercent/100 * nrow(OccurTbl)), replace=TRUE)
    OccurTbl1 = OccurTbl[ll,]
    ## Generate the % points within each class in this table. Write SQL, using sqldf package
    OccurINClass = sqldf("Select count(*), ClassID from OccurTbl1 group by ClassID order by ClassID desc")
    OccurINClass = cbind(OccurINClass, cumsum(OccurINClass[,1]), cumsum(OccurINClass[,1]) / nrow(OccurTbl1))
    names(OccurINClass) = c("OccuCount", "ClassID", "OccuSumBelow", "Percent")

    #### Raster file will contain all the classes in ClassID column, while occurrences table may not have all the classes.
    #### Somehow we have to make the ClassID same as raster file ClassID. This could be done with SQL command update.
    #### but update is not working, not sure about the reason. So I am running the loop which is very very slow.
    XYTable = GenerateXYTable(ClassPixels,OccurINClass)
    #plot(XYTable[,2], XYTable[,3])
    AreaRow = CalculateAUC(XYTable, OmissionVal, x)
    names(AreaRow) <- c("IterationNo", paste("AUC_at_Value_", OmissionVal, sep = ""), "AUC_at_0.5", "AUC_ratio")
    #AreaRow[1] <- as.integer(AreaRow[1])
    return(AreaRow)

  })


}


AreaPredictedPresence <- function(InRast)
{
  ### Now calculate proportionate area predicted under each suitability
  ClassPixels = freq(InRast)
  ### Remove the NA pixels from the table.
  if (is.na(ClassPixels[dim(ClassPixels)[1],1])== TRUE)
  {
    ClassPixels = ClassPixels[-dim(ClassPixels)[1],]
  }

  ClassPixels = ClassPixels[order(nrow(ClassPixels):1),]
  TotPixPerClass = cumsum(ClassPixels[,2])
  PercentPixels = TotPixPerClass / sum(ClassPixels[,2])

  ClassPixels = cbind(ClassPixels, TotPixPerClass, PercentPixels)
  ClassPixels = ClassPixels[order(nrow(ClassPixels):1),]
  return(ClassPixels)
}

## This function generates the XY coordinate table. Using this table areas is calculated.

GenerateXYTable<-function(ClassPixels, OccurINClass)
{
  XYTable = ClassPixels[,c(1,4)]
  XYTable = cbind(XYTable,rep(-1,nrow(XYTable)))
  # names(XYTable) = c("ClassID", "XCoor", "YCoor")
  ## Set the previous value for 1-omission, i.e Y-axis as the value of last
  ## class id in Occurrence table. LAst class id will always smallest
  ## area predicted presence.
  PrevYVal = OccurINClass[1,4]
  for (i in nrow(ClassPixels):1)
  {
    CurClassID = XYTable[i,1]
    YVal = OccurINClass[which(OccurINClass[,2]==CurClassID),4]
    ## print(paste("Length of YVal :",length(YVal), "Current Loop count :", i, "Current value of YVal : ", YVal, sep = " " ))

    if (length(YVal) == 0 )
    {
      XYTable[i,3] = PrevYVal
    }
    else
    {
      XYTable[i,3] = YVal
      PrevYVal = YVal
    }

  }
  ## Add A dummy class id in the XYTable with coordinate as 0,0
  XYTable = rbind(XYTable, c(XYTable[nrow(XYTable),1] + 1, 0, 0))
  XYTable = as.data.frame(XYTable)
  names(XYTable) = c("ClassID", "XCoor", "YCoor")
  ### Now calculate the area using trapezoid method.
  return(XYTable)
}


CalculateAUC <- function(XYTable, OmissionVal, IterationNo)
{
  ## if OmissionVal is 0, then calculate the complete area under the curve. Otherwise calculate only partial area
  if (OmissionVal > 0)
  {
    PartialXYTable = XYTable[which(XYTable[,3] >= OmissionVal),]
    ### Here calculate the X, Y coordinate for the parallel line to x-axis depending upon the OmissionVal
    ### Get the classid which is bigger than the last row of the XYTable and get the XCor and Ycor for that class
    ### So that slope of the line is calculated and then intersection point between line parallel to x-axis and passing through
    ### ommissionval on Y-axis is calculated.
    PrevXCor = XYTable[which(XYTable[,1]==PartialXYTable[nrow(PartialXYTable),1])+1,2]
    PrevYCor = XYTable[which(XYTable[,1]==PartialXYTable[nrow(PartialXYTable),1])+1,3]
    XCor1 = PartialXYTable[nrow(PartialXYTable),2]
    YCor1 = PartialXYTable[nrow(PartialXYTable),3]
    ## Calculate the point of intersection of line parallel to x-asiz and this line. Use the equation of line
    ## in point-slope form y1 = m(x1-x2)+y2
    Slope = (YCor1 - PrevYCor) / (XCor1 - PrevXCor)
    YCor0 = OmissionVal
    XCor0 = (YCor0 - PrevYCor + (Slope * PrevXCor)) / Slope
    ### Add this coordinate in the PartialXYTable with classid greater than highest class id in the table.
    ### Actually class-id is not that important now, only the place where we add this xcor0 and ycor0 is important.
    ### add this as last row in the table
    PartialXYTable = rbind(PartialXYTable, c(PartialXYTable[nrow(PartialXYTable),1]+1, XCor0, YCor0))
  }
  else
  {
    PartialXYTable = XYTable
  } ### if OmissionVal > 0

  ## Now calculate the area under the curve on this table.
  XCor1 = PartialXYTable[nrow(PartialXYTable),2]
  YCor1 = PartialXYTable[nrow(PartialXYTable),3]
  AUCValue = 0
  AUCValueAtRandom = 0
  for (i in (nrow(PartialXYTable)-1):1)
  {
    XCor2 = PartialXYTable[i,2]
    YCor2 = PartialXYTable[i,3]

    # This is calculating the AUCArea for 2 point trapezoid.
    TrapArea = (YCor1 * (abs(XCor2 - XCor1))) + (abs(YCor2 - YCor1) * abs(XCor2 - XCor1)) / 2
    AUCValue = AUCValue + TrapArea
    # now caluclate the area below 0.5 line.
    # Find the slope of line which goes to the point
    # Equation of line parallel to Y-axis is X=k and equation of line at 0.5 is y = x
    TrapAreaAtRandom = (XCor1 * (abs(XCor2 - XCor1))) + (abs(XCor2 - XCor1) * abs(XCor2 - XCor1)) / 2
    AUCValueAtRandom = AUCValueAtRandom + TrapAreaAtRandom
    XCor1 = XCor2
    YCor1 = YCor2

  }

  NewRow = c(IterationNo, AUCValue, AUCValueAtRandom, AUCValue/AUCValueAtRandom)

  return(NewRow)

}

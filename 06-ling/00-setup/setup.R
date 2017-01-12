library(mfdb)
library(tidyverse)
library(Rgadget)
bootstrap <- FALSE
## Create a gadget directory, define some defaults to use with our queries below
gd <- gadget_directory("06-ling/02-base")
mdb<-mfdb('Iceland')#,db_params=list(host='hafgeimur.hafro.is'))

year_range <- 1982:2016

reitmapping <- 
  read.table(
        system.file("demo-data", "reitmapping.tsv", package="mfdb"),
        header=TRUE,
        as.is=TRUE)

defaults <- list(
    area = mfdb_group("1" = unique(reitmapping$SUBDIVISION)),
    timestep = mfdb_timestep_quarterly,
    year = year_range,
    species = 'LIN')


gadgetfile('Modelfiles/time',
           file_type = 'time',
           components = list(list(firstyear = 1982,
                                  firststep=1,
                                  lastyear=2016,
                                  laststep=4,
                                  notimesteps=c(4,3,3,3,3)))) %>% 
  write.gadget.file(gd$dir)

## Write out areafile and update mainfile with areafile location
gadget_areafile(
  size = mfdb_area_size(mdb, defaults)[[1]],
  temperature = mfdb_temperature(mdb, defaults)[[1]]) %>% 
gadget_dir_write(gd,.)


source('06-ling/00-setup/setup-fleets.R')
source('06-ling/00-setup/setup-model.R')
source('06-ling/00-setup/setup-catchdistribution.R')
source('06-ling/00-setup/setup-indices.R')
source('06-ling/00-setup/setup-likelihood.R')


if(bootstrap){
  source('06-ling/00-setup/setup-bootstrap.R')
  file.copy(sprintf('%s/bootrun.R','06-ling/00-setup'),gd$dir)
}

file.copy(sprintf('%s/itterfitter.sh','06-ling/00-setup'),gd$dir)
file.copy(sprintf('%s/run.R','06-ling/00-setup'),gd$dir)
file.copy(sprintf('%s/optinfofile','06-ling/00-setup'),gd$dir)
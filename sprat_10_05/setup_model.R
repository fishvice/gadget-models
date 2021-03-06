# ---------------------------------------------------------------------
# Set the vendace model

## weight length relationship
## lw.constants.spr <- data.frame(a=1.592769e-05,
##                                b=2.620519)
# from WGSAM 2019
lw.constants.spr <- data.frame(a=c(1.5074218,0.96635585,0.91595079)*1e-05,
                               b=2.72)

## lw.constants.spr <- 
##   mfdb_dplyr_sample(mdb) %>% data.frame() %>% 
##   filter(species == defaults.spr$species,
##          data_source == 'pelagic_biasCA_spr',
##          !is.na(weight)) %>% 
##   select(length,weight) %>%
##   collect(n=Inf) %>% 
##   lm(log(weight)~log(length),.) %>% 
##   broom::tidy() %>% 
##   select(estimate)
## ## transport back to right dimension
## lw.constants.spr$estimate[1] <- exp(lw.constants.spr$estimate[1])
## lw.constants.spr <- data.frame(a=lw.constants.spr$estimate[1],
##                                b=lw.constants.spr$estimate[2])

## tmp <- mfdb_dplyr_sample(mdb) %>% data.frame() %>%
##        filter(species == defaults.spr$species,
##               data_source == 'pelagic_biasCA_spr',
##               !is.na(weight)) %>%
##        data.frame()
## ggplot(tmp,
##        aes(length,weight)) +
##    geom_point() +
##    geom_line(data=data.frame(x=tmp$length,
##                              y=lw.constants.spr$a*tmp$length^lw.constants.spr$b),
##              aes(x,y), color=2, lwd=0.6) +
##    facet_wrap(~year)

## initial conditions sigma
init.sigma.spr <- 
  mfdb_dplyr_sample(mdb) %>%  data.frame() %>%
  dplyr::filter(species == defaults.spr$species,
                data_source == 'pelagic_biasCA_spr',
                areacell %in% defaults.spr$area[[1]],
                ## institute %in% 'SLU',
                age >0,
                !is.na(length),
                !is.na(age))  %>%
  dplyr::select(age,length) %>% 
  dplyr::collect(n=Inf) %>% 
  dplyr::group_by(age) %>% 
  dplyr::summarise(ml=mean(length,na.rm=TRUE),ms=sd(length,na.rm=TRUE))

# manually adjust sd age8+
## init.sigma.spr[init.sigma.spr$age >= 8,"ms"] <- 1.00

## initial guess for A50 of the maturity ogive (vector from WGBFAS)
matAtAge <- data.frame(age=0:8, prop=c(0,0.17,0.93,rep(1,6)))
## initial guess for the maturity ogive:
mat.constants.spr <- matAtAge %>%
  nls(prop~1/(1+exp(-b*(age-a50))),. , start=list(b=2,a50=1.5)) %>%
  broom::tidy() %>% 
  select(estimate)
mat.constants.spr <- data.frame(b=mat.constants.spr$estimate[1],
                                a50=mat.constants.spr$estimate[2])
## ggplot(matAtAge,
##        aes(age,prop)) +
##    geom_point() +
##    geom_line(data=data.frame(x=seq(0,8,0.1),
##                              y=1/(1+exp(-mat.constants.spr$b*(seq(0,8,0.1)-mat.constants.spr$a50)))),
##              aes(x,y), color=2, lwd=0.6)


## setup the immature stock first
spr.imm <-
  gadgetstock('sprimm',gd$dir,missingOkay = TRUE) %>%
  gadget_update('stock',
                minage = 0,
                maxage = 2,
                minlength = 3.5,
                maxlength = 12.5,
                dl = 0.5,
                livesonareas = 1) %>%
  gadget_update('refweight',
                data=data_frame(length=seq(.[[1]]$minlength,.[[1]]$maxlength,.[[1]]$dl),
                                mean=lw.constants.spr$a[1]*length^lw.constants.spr$b[1])) %>% 
  gadget_update('doesgrow',
                growthparameters=c(linf='#spr.Linf', 
                                   k=to.gadget.formulae(quote(0.01*spr.k)),
                                   alpha = paste0("Modelfiles/", species_name, ".lwa"),
                                   beta = '#spr.wbeta'),
                beta = to.gadget.formulae(quote(1e1*spr.bbin)),
                maxlengthgroupgrowth = 3) %>% 
  gadget_update('naturalmortality',
                c(0.5,0.44,0.44)) %>%
                ## rep(0.2,3)) %>%  # multispp WGSAM 2019
  gadget_update('initialconditions',
                normalcond = data_frame(age = 1:.[[1]]$maxage,
                                         area = 1,
                                         age.factor = parse(text=sprintf(paste0('exp(-1*(sprimm.M+spr.init.F)*%1$s)*spr.init.%1$s*',matAtAge$prop[age]), age)) %>% 
                                           map(to.gadget.formulae) %>% 
                                           unlist(),   
                                         area.factor = '#sprimm.init.scalar',
                                         mean = parse(text=sprintf('spr.Linf*(1-exp(-1*(0.01*spr.k)*(%1$s-(0.5+log(1-spr.recl/spr.Linf)/(0.01* spr.k)))))',age)) %>% # notice [... -(0.5+log ...] so length scaled considering that rec is in timestep 3
                                             map(to.gadget.formulae) %>% 
                                             unlist(),   
                                         stddev = init.sigma.spr$ms[age],
                                         relcond = 1)) %>% 
  gadget_update('iseaten',1) %>% 
  gadget_update('doesmature',
                maturityfunction = 'continuous',
                maturestocksandratios = 'sprmat 1',
                coefficients = '0 0 #spr.mat1 #spr.mat2') %>% 
  gadget_update('doesmove',
                transitionstocksandratios = 'sprmat 1',
                transitionstep = 4) %>% 
  gadget_update('doesrenew',
                normalparam = data_frame(year = year_range,
                                         step = 3,
                                         area = 1,
                                         age = .[[1]]$minage,
                                         number = parse(text=sprintf('spr.rec.scalar*spr.rec.%s',year)) %>% 
                                           map(to.gadget.formulae) %>% 
                                           unlist(),
                                         mean = parse(text=sprintf('spr.Linf*(1-exp(-1*(0.01*spr.k)*(%1$s-(0+log(1-spr.recl/spr.Linf)/(0.01* spr.k)))))',age)) %>% # notice [... -(0+log ...] so recl is mean length at recr time
                                             map(to.gadget.formulae) %>% 
                                             unlist(),   
                                         stddev = '#spr.rec.sd',
                                         alpha = '(* 1e-6 #spr.walpha1)',
                                         beta = '#spr.wbeta'))
spr.imm$initialconditions$minage <- 1

## setup the mature stock
spr.mat <-
  gadgetstock('sprmat',gd$dir,missingOkay = TRUE) %>%
  gadget_update('stock',
                minage = 1,
                maxage = 10,
                minlength = 8.5,
                maxlength = 17.5,
                dl = 0.5,
                livesonareas = 1) %>%
  gadget_update('refweight',
                data=data_frame(length=seq(.[[1]]$minlength,.[[1]]$maxlength,.[[1]]$dl),
                                mean=lw.constants.spr$a[1]*length^lw.constants.spr$b[1])) %>% 
  gadget_update('doesgrow',
                growthparameters=c(linf='#spr.Linf', 
                                   k=to.gadget.formulae(quote(0.01*spr.k)),
                                   alpha = paste0("Modelfiles/", species_name, ".lwa"),
                                   beta = '#spr.wbeta'),
                beta = to.gadget.formulae(quote(1e1*spr.bbin)),
                maxlengthgroupgrowth = 3) %>% 
  gadget_update('naturalmortality',
                c(0.44,0.44,0.44,0.43,0.42,0.42,0.41,0.41,0.41,0.41)) %>%
                ## rep(0.2,10)) %>%  # multispp WGSAM 2019
  gadget_update('initialconditions',
                normalcond = data_frame(age = .[[1]]$minage:8,
                                         area = 1,
                                         age.factor = parse(text=sprintf(paste0('exp(-1*(sprmat.M+spr.init.F)*%1$s)*spr.init.%1$s*', matAtAge$prop[age]),age)) %>% 
                                           map(to.gadget.formulae) %>% 
                                           unlist(),   
                                         area.factor = '#sprmat.init.scalar',
                                         mean = parse(text=sprintf('spr.Linf*(1-exp(-1*(0.01*spr.k)*(%1$s-(0.5+log(1-spr.recl/spr.Linf)/(0.01* spr.k)))))',age)) %>% # notice [... -(0.5+log ...] so length scaled considering that rec is in timestep 3
                                             map(to.gadget.formulae) %>% 
                                             unlist(),   
                                         stddev = init.sigma.spr$ms[age],
                                         relcond = 1)) %>% 
  gadget_update('iseaten',1)
spr.mat$initialconditions$maxage <- 8


## write to file
spr.imm %>% 
  write.gadget.file(gd$dir)
spr.mat %>% 
  write.gadget.file(gd$dir)

# write timevariable L-W
tmp <- gadgetfile(file_name=paste0("Modelfiles/", species_name, ".lwa"),
                  file_type="timevariable",
                  components=list(
                             list(
                                  "LWalpha",
                                  data = data.frame(
                                         year = c(1974,1990,1997),
                                         step = 1,
                                         value = paste0('(* 1e-6 #spr.walpha', 1:3, ')'),
                                         stringsAsFactors = TRUE))))
tmp %>% 
  write.gadget.file(gd$dir)

# ---------------------------------------------------------------------
Sys.setenv(GADGET_WORKING_DIR=normalizePath(gd$dir))
callGadget(s=1,log = 'init.log') #ignore.stderr = FALSE,

## update the input parameters with sane initial guesses
read.gadget.parameters(sprintf('%s/params.out',gd$dir)) %>% 
  ## init_guess('spr.rec.[0-9]',1,0.001,1000,1) %>%
  ## init_guess('spr.init.[0-9]',1,0.001,1000,1) %>%
  init_guess('rec.[0-9]|init.[0-9]',1,0.001,100,1) %>%
  init_guess('spr.recl',7.7,5,15,0) %>%  # from old runs
  init_guess('spr.rec.sd',0.9, 0.01, 15,0) %>%   # from old runs
  init_guess('spr.Linf',13.25909, 12, 25,0) %>%  # from CA BIAS
  init_guess('spr.k$',66.79, 0.1, 100,1) %>%   # from CA BIAS
  init_guess('spr.bbin',0.9, 0.001, 50, 1) %>% 
  init_guess('spr.com.alpha', 0.9,  0.1, 3, 1) %>% 
  init_guess('spr.com.l50',10,7,18,1) %>% 
  init_guess('spr.aco.alpha', 0.9,  0.1, 2, 1) %>% 
  init_guess('spr.aco.l50',10,7,15,1) %>% 
  init_guess('spr.walpha1',1e6 * lw.constants.spr$a[1], 1, 100, 1) %>% 
  init_guess('spr.walpha2',1e6 * lw.constants.spr$a[2], 1, 100, 1) %>% 
  init_guess('spr.walpha3',1e6 * lw.constants.spr$a[3], 1, 100, 1) %>% 
  init_guess('spr.wbeta',lw.constants.spr$b[1], 2, 4,0) %>% 
  init_guess('sprimm.M$',0.2,0.001,1,0) %>% 
  init_guess('sprmat.M$',0.2,0.001,1,0) %>% 
  init_guess('spr.rec.scalar',1e6,1,1e8,0) %>% 
  init_guess('sprimm.init.scalar',1e6,1,1e8,0) %>% 
  init_guess('sprmat.init.scalar',1e5,1,1e8,0) %>% 
  init_guess('spr.init.F',0.3,0.1,1,0) %>%
  init_guess('spr.mat1',mat.constants.spr$b,0.1,10,0) %>%
  init_guess('spr.mat2',mat.constants.spr$a50,1,30,0) %>% 
write.gadget.parameters(.,file=sprintf('%s/params.in',gd$dir))

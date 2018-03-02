# Parses the experiment's NGINX log file.
read.accesslog <- function(f) {
  # https://lincolnloop.com/blog/tracking-application-response-time-nginx/
  al <- read.csv(f, sep=";", colClasses=c("upstream_response_time"="character"))
  # request processing time in seconds with a milliseconds resolution;
  # time elapsed between the first bytes were read from the client and
  # the log write after the last bytes were sent to the client
  # http://nginx.org/en/docs/http/ngx_http_log_module.html.
  al$request_time <- al$request_time * 1000 # Making it milliseconds.
  # Calculating elapsed time. It is more useful than timestamp.
  al <- al %>% arrange(timestamp)
  al$exp_dur_ms <- c(0, al$timestamp[2:NROW(al)]-al$timestamp[1]) * 1000
  al$hop1 <- sub(',.*$', '', al$upstream_response_time)
  al$hop1 <- as.numeric(al$hop1)*1000
  al$hop2 <- sub('^.*,', '', al$upstream_response_time)
  al$hop2 <- as.numeric(al$hop2)*1000
  al$num_hops <- str_count(al$upstream_response_time, ',')+1
  return(al)
}

accesslog <- function(outdir, exp, n) {
  al <- read.accesslog(paste(outdir, "/al_", exp, "_1.log", sep=""))
  al["expid"] <- 1
  al["id"] <- seq(1,NROW(al))
  if (n == 1) {
    return(al)
  }
  for (i in 2:n) {
    aux <- read.accesslog(paste(outdir, "/al_", exp, "_", i,".log", sep=""))
    aux["expid"] <- i
    aux["id"] <- seq(1,NROW(aux))
    al <- rbind(al, aux)
  }
  return(al)
}

ci.median <- function(x) {
  wt <- wilcox.test(sample(x, 1000), conf.level=0.95, conf.int = T)
  r <- wt$conf.int
  names(r) <- c("ymin", "ymax")
  return(r)
}

p99 <- function(x) {
  return(quantile(x, 0.99))
}

p999 <- function(x) {
  return(quantile(x, 0.999))
}

p9999 <- function(x) {
  return(quantile(x, 0.9999))
}

ci.p <- function(x, p) {
  ci.fun <- function(data, indices) {
    return(c(quantile(data[indices], c(p)), var(data)))
  }
  b <- boot(x, ci.fun, R=RESAMPLES)
  bci <- boot.ci(b)
  return(data.frame("ymin"=c(bci$basic[4]), "ymax"=c(bci$basic[5])))
}

ci.p99 <- function(x) {
  return(ci.p(x, 0.99))
}

ci.p999 <- function(x) {
  return(ci.p(x, 0.999))
}

ci.p9999 <- function(x) {
  return(ci.p(x, 0.9999))
}
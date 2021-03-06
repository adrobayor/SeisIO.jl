using Base.Test, Compat
path = Base.source_dir()

# Seedlink with command-line stations
println("...SeedLink! TIME mode...")
sta = ["CC.SEP", "UW.HDW"]

# Checking
tf = has_live_stream(sta, "rtserve.iris.washington.edu")

# To ensure precise timing, we'll pass d0 and d1 as strings
st = 0.0
en = 60.0
dt = en-st
(d0,d1) = parsetimewin(st,en)

S = SeisData()
SeedLink!(S, sta, mode="TIME", r=10.0, s=d0, t=d1)
println("...first link initialized...")

# Seedlink with a config file
config_file = path*"/SampleFiles/seedlink.conf"
SeedLink!(S, config_file, r=10.0, mode="TIME", s=d0, t=d1)
println("...second link initialized...")

# Seedlink with a config string
SeedLink!(S, "CC.VALT..???, UW.ELK..EHZ", mode="TIME", r=10.0, s=d0, t=d1)
println("...third link initialized...")

# This takes time
println(string("Sleeping for ", 2*dt, " seconds while S fills..."))
sleep(dt)
for i = 1:length(S.c)
  close(S.c[i])
end
@assert(isempty(S)==false)

# Synchronize (the reason we used d0,d1 above)
sleep(dt)
println("...moving on now.")
sync!(S, s=d0, t=d1)

# Are they about the same time length? (should be within 1 samp at longest fs)
L = [length(S.x[i])/S.fs[i] for i = 1:S.n]
t = [S.t[i][1,2] for i = 1:S.n]
L_min = minimum(L)
L_max = maximum(L)
t_min = minimum(t)
t_max = maximum(t)
@assert(L_max - L_min <= maximum(1./S.fs))
@assert(t_max - t_min <= maximum(1./S.fs))

println("...SeedLink! DATA mode...")
T = SeisData()
println("...link 1: command-line station list...")
SeedLink!(T, sta, mode="DATA", r=11.1)
println("...link 2: station file...")
SeedLink!(T, config_file, mode="DATA", r=13.3)
sleep(dt)
for i = 1:length(T.c)
  close(T.c[i])
end
sleep(dt/2.0)
@assert(isempty(T)==false)
println("...moving on now.")
sync!(T)

println("...done!")

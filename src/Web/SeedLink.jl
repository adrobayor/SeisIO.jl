# ========================================================================
# Utility functions not for export
function getSLver(vline::String)
  # Versioning will break if SeedLink switches to VV.PPP.NNN format
  ver = 0.0
  vinfo = split(vline)
  for i in vinfo
    if startswith(i, 'v')
      try
        ver = parse(i[2:end])
        return ver
      end
    end
  end
end

function check_sta_exists(sta::Array{String,1}, xstr::String)
  xstreams = get_elements_by_tagname(root(parse_string(xstr)), "station")
  xid = join([join([attribute(xstreams[i], "network"),attribute(xstreams[i], "name")],'.') for i=1:length(xstreams)], ' ')
  N = length(sta)
  x = falses(N)
  for i = 1:1:N
    id = split(sta[i], '.', keep=true)
    sid = join(id[1:2],'.')
    if contains(xid, sid)
      x[i] = true
    end
  end
  return x
end

function check_stream_exists(S::Array{String,1}, xstr::String; g=7200::Real)
  a = ["seedname","location","type"]
  N = length(S)
  x = falses(N)

  xstreams = get_elements_by_tagname(root(parse_string(xstr)), "station")
  xid = [join([attribute(xstreams[i], "network"),attribute(xstreams[i], "name")],'.') for i=1:length(xstreams)]
  for i = 1:1:N
    # Assumes the combination of network name and station name is unique
    id = split(S[i], '.', keep=true)
    sid = join(id[1:2],'.')
    K = findfirst(xid.==sid)
    if K > 0
      t = Inf

      # Syntax requires that contains(string, "") returns true for any string
      ll = ""
      cc = ""
      dd = ""
      if length(id) > 2
        ll = replace(id[3],"?","")
        if length(id) > 3
          cc = replace(id[4],"?","")
          if length(id) > 4
            dd = replace(id[5],"?","")
          end
        end
      end
      p = [cc, ll, dd]

      R = get_elements_by_tagname(xstreams[K], "stream")
      if !isempty(R)
        for j = 1:1:length(R)
          if prod([contains(attribute(R[j], a[i]), p[i]) for i=1:length(p)]) == true
            te = replace(attribute(R[j], "end_time"), " ", "T")
            t = min(t, time()-d2u(Dates.DateTime(te)))
          end
        end
      end

      # Treat station as "present" if there's a match
      if minimum(t) < g
        x[i] = true
      end
    end
  end
  return x
end
# ========================================================================


"""
    info_xml = SL_info(level=LEVEL::String, u=URL::String, p=PORT::Integer)

Retrieve XML output of SeedLink command "INFO `LEVEL`" from server `URL:PORT`. Returns formatted XML. `LEVEL` must be one of "ID", "CAPABILITIES", "STATIONS", "STREAMS", "GAPS", "CONNECTIONS", "ALL".

"""
function SL_info(level::String,                    # level
                 u::String;                        # url
                 p=18000::Integer                  # port
                 )
  conn = connect(TCPSocket(),u,p)
  write(conn, string("INFO ", level, "\r"))
  eof(conn)
  # B = takebuf_array(conn.buffer)
  B = take!(conn.buffer) # This is really counterintuitive syntax, if it even works...
  N = length(B)
  while (Char(B[end]) != '\0' || rem(N,520) > 0)
    eof(conn)
    append!(B, take!(conn.buffer)) # This is really counterintuitive syntax, if it even works...
    N = length(B)
  end
  close(conn)
  buf = IOBuffer(N)
  write(buf, B)
  seekstart(buf)
  xml_str = ""
  while !eof(buf)
    skip(buf, 64)
    xml_str *= join(map(x -> Char(x), read(buf, UInt8, 456)))
  end
  return replace(String(xml_str),"\0","")
end

"""
  has_sta(sta::String, u::String; p=18000::Integer)

Check that streams exist at url `u` for stations `sta`, formatted NET.STA. Use "?" to match any single character. Returns `true` for stations that exist. `sta` can also be the name of a valid config file.

    X = has_sta(sta::Array{String,1}, u)

Check that stations in `sta` (formatted NET.STA) are available via SeedLink from `u`. Returns a BitArray with one value per entry in `sta.`

"""
function has_sta(C::String, u::String; p=18000::Integer)
  sta,pat = SeisIO.parse_sl(SeisIO.parse_chstr(C))
  for i = 1:length(sta)
    s = split(sta[i], " ")
    sta[i] = join([s[2],s[1]],'.')
  end
  return check_sta_exists(sta, SL_info("STATIONS", u, p=p))
end
has_sta(sta::Array{String,1}, u::String; p=18000::Integer) = check_sta_exists([replace(i, " ", ".") for i in sta], SL_info("STATIONS", u, p=p))
has_sta(sta::Array{String,2}, u::String; p=18000::Integer) = check_sta_exists([join(sta[i,:],'.') for i=1:size(sta,1)], SL_info("STATIONS", u, p=p))


"""
X = has_live_stream(cha::String, u::String)

Check that streams with recent data exist at url `u` for channel spec `cha`, formatted NET.STA.LOC.CHA.DFLAG, e.g. "UW.TDH..EHZ.D, CC.HOOD..BH?.E". Use "?" to match any single character. Returns `true` for streams with recent data.

`cha` can also be the name of a valid config file.

    X = has_live_stream(cha::Array{String,1}, u::String)

Check that streams with recent data exist at url `u` for channel spec `cha`, formatted NET.STA.LOC.CHA.DFLAG, e.g. ["UW.TDH..EHZ.D",  "CC.HOOD..BH?.E"]. Use "?" to match any single character. Returns `true` for streams with recent data.

    X = has_live_stream(cha::Array{String,1}, u::String, p=N::Int, g=G::Real)

As above, with keywords to set port number `N` (default: 18000) and timeout `M` seconds (default: 7200). If t > G seconds since last packet received, a stream is considered dead.

  X = has_live_stream(sta::Array{String,1}, sel::Array{String,1}, u::String, p=N::Int, g=G::Real)

If two arrays are passed to has_live_stream, the first should be formatted as SeedLink STATION patterns (formated "SSSSS NN", e.g. ["TDH UW", "VALT CC"]); the second be an array of SeedLink selector patterns (formatted LLCCC.D, e.g. ["??EHZ.D", "??BH?.?"]).
"""
function has_live_stream(sta::Array{String,1}, pat::Array{String,1}, u::String; p=18000::Int, g=7200::Real)
  for i = 1:length(sta)
    s = split(sta[i], " ")
    c = split(pat[i], '.')
    cha[i] = join([s[2],s[1],c[1][1:2],c[1][3:5],c[2]],'.')
  end
  return check_stream_exists(cha, SL_info("STREAMS", u, p=p), g=g)
end
function has_live_stream(sta::String, u::String; p=18000::Integer, g=7200::Real)
  sta,pat = SeisIO.parse_sl(SeisIO.parse_chstr(sta))
  return has_live_stream(sta, pat, u, p=p,g=g)
end
has_live_stream(sta::Array{String,1}, u::String; p=18000::Int, g=7200::Real) = check_stream_exists(sta, SL_info("STREAMS", u, p=p), g=g)
has_live_stream(sta::Array{String,2}, u::String; p=18000::Integer, g=7200::Real) = check_stream_exists([join(sta[i,:],'.') for i=1:size(sta,1)], SL_info("STREAMS", u, p=p), g=g)

"""
    SeedLink!(S, sta)

Begin acquiring SeedLink data to SeisData structure `S`. New channels are added to `S` automatically based on `sta`. Connections are added to S.c.

    S = SeedLink(sta)

Create a new SeisData structure `S` to acquire SeedLink data. Connection will be in S.c[1].

### INPUTS
* `S`: SeisData object
* `sta`: Array{String, 1} formatted NET.STA.LOC.CHA.DFLAG, e.g. ["UW.TDH..EHZ.D",  "CC.HOOD..BH?.E"]. Use "?" to match any single character; leave LOC and CHA fields blank to select all. Don't use "\*" for wildcards, it isn't valid.

*Note*: When finished, close connection manually with `close(S.c[n])` where n is connection \#. If `w=true`, the next attempted packet dump after closing `C` will close the output file automatically.

### KEYWORD ARGUMENTS
Specify as `kw=value`, e.g., `SeedLink!(S, sta, mode="TIME", r=120)`.

| Name   | Default | Type            | Description                      |
|:-------|:--------|:----------------|:---------------------------------|
| f      | 0x02    | UInt8           | safety check level (3)           |
| g      | 3600    | Real            | max. gap since last packet [s]   |
| ka     | 600     | Real            | keepalive interval [s]           |
| mode   | "DATA"  | String          | TIME, DATA, or FETCH             |
| p      | 18000   | Integer         | port number                      |
| r      | 20      | Real            | base refresh interval [s]        |
| s      | 0       | (1)             | start time (TIME or FETCH only)  |
| x      | true    | Bool            | exits on error?                  |
| t      | 300     | (1)             | end time (TIME only)             |
| u      | (iris)  | String          | url, no "http://"                |
| v      | 0       | Int             | verbosity                        |
| w      | false   | Bool            | write raw packets to disk? (6)   |

(1) Type `?parsetimewin` for time window syntax help
(2) If `length(patt) < length(sta)`, `patt[end]` repeats to `length(sta)`
(3) 0x01 = check if stations exist at `u`; 0x02 = check for recent data at `u`
(4) A stream with no data for `g` seconds is considered offline if `f=0x02`.
(5) File name is auto-generated. Each `SeedLink!` call uses a unique file.
"""
function SeedLink!(S::SeisData,
  sta::Array{String,1},
  patts::Array{String,1};
  f=0x00::UInt8,                                      # safety check level
  g=7200::Real,                                       # maximum gap
  ka=240::Real,                                       # keepalive interval (s)
  mode="DATA"::String,                                # SeedLink mode
  p=18000::Integer,                                   # port
  r=20::Real,                                         # refresh interval (s)
  s=0::Union{Real,DateTime,String},                   # start (time/dialup mode)
  t=300::Union{Real,DateTime,String},                 # end (time mode only)
  u="rtserve.iris.washington.edu"::String,            # url
  x=true::Bool,                                       # exit on error?
  v=0::Int,                                           # verbosity level
  w=false::Bool)


  # ==========================================================================
  # init, warnings, sanity checks
  Ns = size(sta,1)

  # Refresh interval
  r = maximum([r, eps()])
  r < 10 && warn(string("r = ", r, " < 10 s; Julia may freeze if no packets arrive between consecutive read attempts."))

  # keepalive interval
  if ka < 240
    warn("KeepAlive interval increased to 240s as per IRIS netiquette guidelines.")
    ka = 240
  end

  if f==0x02
    v>0 && println("Checking for recent matching streams (may take 60 s)...")
    h = has_live_stream(sta, patts, u, p=p, g=g)
  elseif f==0x01
    v>0 && println("Checking that request exists (may take 60 s)...")
    h = has_sta(sta, u, p=p)
  else
    h = trues(Ns)
  end

  for i = Ns:-1:1
    if !h[i]
      warn(string(u, " doesn't currently have ", sta[i], "; deleted from req."))
      deleteat!(sta, i)
      deleteat!(patts,i)
    end
  end
  Ns = length(sta)
  if Ns == 0
    warn("No channels in the current request were found. Exiting SeedLink!...")
    return S
  end

  # Source for logging
  src = join([u,p],':')

  # ==========================================================================
  # connection and server info retrieval
  push!(S.c, connect(TCPSocket(),u,p))
  q = length(S.c)

  # version, server info
  write(S.c[q],"HELLO\r")
  vline = readline(S.c[q])
  sline = readline(S.c[q])
  ver = getSLver(vline)

  # version-based compatibility checks (unlikely that such a server exists)
  if ver < 2.5 && length(sta) > 1
    error(@sprintf("Multi-station mode unsupported in SeedLink v%.1f", ver))
  elseif ver < 2.92 && mode == "TIME"
    error(@sprintf("Mode \"TIME\" not available in SeedLink v%.1f", ver))
  end
  (v > 1) && println("Version = ", ver)
  (v > 1) && println("Server = ", strip(sline,['\r','\n']))
  # ==========================================================================

  # ==========================================================================
  # handshaking

  # create mode string and filename for -w
  (d0,d1) = parsetimewin(s,t)
  s = join(split(d0,r"[\-T\:\.]")[1:6],',')
  t = join(split(d1,r"[\-T\:\.]")[1:6],',')
  if mode in ["TIME", "FETCH"]
    if mode == "TIME"
      if (DateTime(d1)-u2d(time())).value < 0
        warn("End time < time() in TIME mode; SeedLink may receive no data!")
      end
      m_str = string("TIME ", s, " ", t, "\r")
    else
      m_str = string("FETCH ", s, "\r")
    end
  else
    m_str = string("DATA\r")
  end
  fname = hashfname([join(sta,','), join(patts,','), s, t, m_str], "mseed")

  if w
    (v > 0) && println(string("Raw packets will be written to file ", fname, " in dir ", realpath(pwd())))
    fid = open(fname, "w")
  end

  # pass strings to server; check responses carefully
  for i = 1:Ns
    # pattern selector
    sel_str = string("SELECT ", patts[i], "\r")
    (v > 1) && println("Sending: ", sel_str)
    write(S.c[q], sel_str)
    sel_resp = readline(S.c[q])
    if contains(sel_resp,"ERROR")
      warn(string("Error in select string ", patts[i], " (", sta[i], "previous selector, ", i==1?"*":patts[i-1], " used)."))
      if x
        close(S.c[q])
        error("Strict mode specified; exit w/error.")
        deleteat!(S.c, q)
        return S
      end
    end
    (v > 1) && @printf(STDOUT, "Response: %s", sel_resp)

    # station selector
    sta_str = string("STATION ", sta[i], "\r")
    (v > 1) && println("Sending: ", sta_str)
    write(S.c[q], sta_str)
    sta_resp = readline(S.c[q])
    if contains(sel_resp,"ERROR")
      warn(string("Error in station string ", sta[i], " (station excluded)."))
      close(S.c[q])
      error("Strict mode specified; exit w/error.")
      deleteat!(S.c, q)
      return S
    end
    (v > 1) && @printf(STDOUT, "Response: %s", sta_resp)

    # mode
    (v > 1) && println("Sending: ", m_str)
    write(S.c[q], m_str)
    m_resp = readline(S.c[q])
    (v > 1) && @printf(STDOUT, "Response: %s", m_resp)
  end
  write(S.c[q],"END\r")
  # ==========================================================================

  # ==========================================================================
  # data transfer
  k = @task begin
    j = 0
    while true
      if !isopen(S.c[q])
        println(STDOUT, timestamp(), ": SeedLink connection closed.")
        w && close(fid)
        break
      else

        #= use of rand() makes it almost impossible for multiple SeedLink
        connections to result in one sleeping indefinitely. =#
        τ = ceil(Int, r*(1+rand()))
        sleep(τ)
        eof(S.c[q])
        N = floor(Int, nb_available(S.c[q])/520)
        if N > 0
          buf = IOBuffer(read(S.c[q], UInt8, 520*N))
          if w
            write(fid, copy(buf))
          end
          (v > 1) && @printf(STDOUT, "%s: Processing packets ", string(now()))
          while !eof(buf)
            pkt_id = String(read(buf,UInt8,8))
            parserec!(S, buf, false, v)
            (v > 1) && @printf(STDOUT, "%s, ", pkt_id)
          end
          (v > 1) && @printf(STDOUT, "\b\b...done current packet dump.\n")
        end

        # SeedLink (non-standard) keep-alive gets sent every a seconds
        j += τ
        if j ≥ ka
          # Secondary "isopen" loop avoids possible error from race condition
          # maybe a Julia bug? First encountered 2017-01-03
          if isopen(S.c[q])
            j -= ka
            write(S.c[q],"INFO ID\r")
          end
        end

      end
    end
  end
  Base.sync_add(k)
  Base.enq_work(k)
  # ========================================================================

  return S
end
function SeedLink!(S::SeisData, C::Union{String,Array{String,1},Array{String,2}};
f=0x00::UInt8,                                      # safety check level
g=7200::Real,                                       # maximum gap
ka=240::Real,                                       # keepalive interval (s)
mode="DATA"::String,                                # SeedLink mode
p=18000::Integer,                                   # port
r=20::Real,                                         # refresh interval (s)
s=0::Union{Real,DateTime,String},                   # start (time/dialup mode)
t=300::Union{Real,DateTime,String},                 # end (time mode only)
u="rtserve.iris.washington.edu"::String,            # url
x=true::Bool,                                       # exit on error?
v=0::Int,                                           # verbosity level
w=false::Bool)

  if isa(C, String)
    sta,pat = SeisIO.parse_sl(SeisIO.parse_chstr(C))
  elseif ndims(C) == 1
    sta,pat = SeisIO.parse_sl(SeisIO.parse_charr(C))
  else
    sta, pat = parse_sl(C)
  end
  SeedLink!(S, sta, pat, u=u, p=p, mode=mode, r=r, ka=ka, s=s, t=t, f=f, x=x, v=v, w=w)
  return S
end

function SeedLink(S::SeisData, sta::Array{String,1}, pat::Array{String,1};
  f=0x00::UInt8,                                      # safety check level
  g=7200::Real,                                       # maximum gap
  ka=240::Real,                                       # keepalive interval (s)
  mode="DATA"::String,                                # SeedLink mode
  p=18000::Integer,                                   # port
  r=20::Real,                                         # refresh interval (s)
  s=0::Union{Real,DateTime,String},                   # start (time/dialup mode)
  t=300::Union{Real,DateTime,String},                 # end (time mode only)
  u="rtserve.iris.washington.edu"::String,            # url
  x=true::Bool,                                       # exit on error?
  v=0::Int,                                           # verbosity level
  w=false::Bool)

  S = SeisData()
  SeedLink!(S, sta, pat, u=u, p=p, mode=mode, r=r, ka=ka, s=s, t=t, f=f, x=x, v=v, w=w)
  return S
end

function SeedLink(C::Union{String,Array{String,1},Array{String,2}};
  f=0x00::UInt8,                                      # safety check level
  g=7200::Real,                                       # maximum gap
  ka=240::Real,                                       # keepalive interval (s)
  mode="DATA"::String,                                # SeedLink mode
  p=18000::Integer,                                   # port
  r=20::Real,                                         # refresh interval (s)
  s=0::Union{Real,DateTime,String},                   # start (time/dialup mode)
  t=300::Union{Real,DateTime,String},                 # end (time mode only)
  u="rtserve.iris.washington.edu"::String,            # url
  x=true::Bool,                                       # exit on error?
  v=0::Int,                                           # verbosity level
  w=false::Bool)

  S = SeisData()
  if isa(C, String)
    sta,pat = SeisIO.parse_sl(SeisIO.parse_chstr(C))
  elseif ndims(C) == 1
    sta,pat = SeisIO.parse_sl(SeisIO.parse_charr(C))
  else
    sta, pat = parse_sl(C)
  end
  SeedLink!(S, sta, pat, u=u, p=p, mode=mode, r=r, ka=ka, s=s, t=t, f=f, x=x, v=v, w=w)
  return S
end

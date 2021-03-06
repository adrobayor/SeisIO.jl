using Base.Test, Compat
const μs = 1.0e-6
const datafields = [:name, :id, :fs, :gain, :loc, :misc, :notes, :resp, :src, :units, :t, :x]
const hdrfields = [:id, :ot, :loc, :mag, :int, :mt, :np, :pax, :src, :notes, :misc]

test_fields_preserved(S1::SeisData, S2::SeisData, x::Int, y::Int) = @assert(minimum([getfield(S1,f)[x]==getfield(S2,f)[y] for f in datafields]))
test_fields_preserved(S1::SeisChannel, S2::SeisData, y::Int) =
  @assert(minimum([getfield(S1,f)==getfield(S2,f)[y] for f in datafields]))

function sizetest(S::SeisData, nt::Int)
  @test ≈(S.n, nt)
  @test ≈(maximum([length(getfield(S,i)) for i in datafields]), nt)
  @test ≈(minimum([length(getfield(S,i)) for i in datafields]), nt)
  return nothing
end

function mktestseis()
  L0 = 30
  L1 = 10
  os = 5
  tt = time()
  t1 = round(Int, tt/μs)
  t2 = round(Int, (L0+os)/μs) + t1

  S = SeisData(5)
  S.id = ["XX.TMP01.00.BHZ","XX.TMP01.00.BHN","XX.TMP01.00.BHE","CC.LON..BHZ","UW.SEP..EHZ"]
  S.fs = collect(Main.Base.Iterators.repeated(100.0, S.n))
  S.fs[4] = 20.0
  for i = 1:S.n
    os1 = round(Int, 1/(S.fs[i]*μs))
    S.x[i] = randn(Int(L0*S.fs[i]))
    S.t[i] = [1 t1+os1; length(S.x[i]) 0]
  end

  T = SeisData(4)
  T.name = ["Channel 6", "Channel 7", "Channel 8", "Channel 9"]
  T.id = ["XX.TMP02.00.EHZ","XX.TMP03.00.EHN","CC.LON..BHZ","UW.SEP..EHZ"]
  T.fs = collect(Main.Base.Iterators.repeated(100.0, T.n))
  T.fs[3] = 20.0
  for i = 1:T.n
    T.x[i] = randn(Int(L1*T.fs[i]))
    T.t[i] = [1 t2; length(T.x[i]) 0]
  end
  return (S,T)
end

# Tests
println(STDOUT,"seisdata...")
C = SeisData()

(S,T) = mktestseis()

println(STDOUT,"getindex...")
i_targ = 3
C = S[i_targ]
test_fields_preserved(C,S,i_targ)

D = S[i_targ:i_targ+1]
test_fields_preserved(D,S,2,i_targ+1)

println(STDOUT,"in...")
@assert("XX.TMP01.00.BHZ" in S.id)

println(STDOUT,"findid...")
@test ≈(findid("CC.LON..BHZ",S),findid(S,"CC.LON..BHZ"))
@test ≈(findid(S,"CC.LON..BHZ"),4)
@test ≈(findid(S,C),3)

println(STDOUT,"setindex!...")
A = SeisData(3)
setindex!(A, C, 3)
A[1:2]=D
test_fields_preserved(A, S, 2, i_targ+1)
test_fields_preserved(C, S, 3)

println(STDOUT,"isempty...")
D = SeisData()
@assert(isempty(D))

println(STDOUT,"equality (reflexive)...")
@assert(S==S)

println(STDOUT,"append!...")
append!(S, T)
sizetest(S, 9)

println(STDOUT,"deleteat!, delete! (by channel index)...")
C = deepcopy(S[4])
deleteat!(S, 4)
sizetest(S, 8)
@test ≈(findfirst(S.name.==C.name),0)

C = deepcopy(S[3:4])
delete!(S,3:4)
nt = 6
@test ≈(S.n, nt)
@test ≈(maximum([length(getfield(S,i)) for i in datafields]), nt)
@test ≈(minimum([length(getfield(C,i)) for i in datafields]), 2)
@test ≈(findfirst(S.name.==C.name[1]).*findfirst(S.id.==C.id[1]),0)
@test ≈(findfirst(S.name.==C.name[2]).*findfirst(S.id.==C.id[2]),0)

println(STDOUT,"deleteat!, delete! (id string)...")
s = "CC.LON..BHZ"
delete!(S, s)
sizetest(S, 5)

s = r"EH"
S -= s
sizetest(S, 2)

println(STDOUT,"merge!, no common channels...")
(S,T) = mktestseis()
A=deepcopy(S[5])
B=deepcopy(T[4])
T*=S[1]
sizetest(T, 5)

println(STDOUT,"merge!, one common channel...")
S*=T[2]
sizetest(S, 5)

println(STDOUT,"...time merge functionality...")
@test ≈(S.t[2][2,1], 1+length(A.x))
@test ≈(S.t[2][2,2], (5-1/S.fs[2])*1.0e6)

println(STDOUT,"merge!, common channels + seisdata splat...")
(S,T) = mktestseis()
U = SeisData(S,T)
merge!(U)
sizetest(U, 7)

println(STDOUT,"merge! (two independent channels)...")
println(STDOUT,"...w/no common channels...")
U = S[1] * T[2]
sizetest(U, 2)

println(STDOUT,"..two identical channel ids...")
U = S[4] * T[3]
@assert(typeof(U)==SeisData)
@assert(U.id[1]==S.id[4])
@assert(U.id[1]==T.id[3])

println(STDOUT,"pull...")
C = pull(S,4)
@assert(C.name=="Channel 4")
@assert(S.n==4)
@assert(findfirst(S.name.=="Channel 4")==0)

println(STDOUT,"note!...")
str1 = "ADGJALMGFLSFMGSLMFLChannel 5 sucks"
str2 = "HIGH SNR ON THIS CHANNEL"
note!(S,str2)
note!(S,str1)
@assert(findfirst([maximum([contains(S.notes[i][j],str1) for j = 1:length(S.notes[i])]) for i = 1:S.n])==4)
@assert(length(find([maximum([contains(S.notes[i][j],str2) for j = 1:length(S.notes[i])]) for i = 1:S.n]))==S.n)

# merge test: when we merge, does each field have exactly 7 entries?
merge!(S,T)
n_targ = 7
@test ≈(S.n, n_targ)
@test ≈(maximum([length(getfield(S,i)) for i in datafields]), n_targ)
@test ≈(minimum([length(getfield(S,i)) for i in datafields]), n_targ)

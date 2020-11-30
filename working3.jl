###############################################################################
# 			APPROXIMATING DEFAULT ECONOMIES WITH NEURAL NETWORKS
###############################################################################

############################################################
# [0] Including our module
############################################################
using Random, Distributions, Statistics, LinearAlgebra, StatsBase, Parameters, Flux, ColorSchemes, Gadfly
using Cairo, Fontconfig, Tables, DataFrames, Compose
include("supcodes.jl");

############################################################
# [1]  FUNCTIONS TO BE USED
############################################################
# ----------------------------------------------------------
# [1.a] Choosing unique states from the simulated data
# ----------------------------------------------------------
myunique(data) = begin
    dataTu = [Tuple(data[i, :]) for i = 1:size(data)[1]]
    dataTu = unique(dataTu)
    dataTu = [[dataTu[i]...]' for i = 1:length(dataTu)]
    data = [vcat(dataTu...)][1]
    return data
end
# ----------------------------------------------------------
# [1.b]  Normalization:
#     ̃x = (x - 1/2(xₘₐₓ + xₘᵢₙ)) /(1/2(xₘₐₓ - xₘᵢₙ))
# ----------------------------------------------------------
mynorm(x) = begin
    ux = maximum(x, dims = 1)
    lx = minimum(x, dims = 1)
    nx = (x .- 0.5 * (ux + lx)) ./ (0.5 * (ux - lx))
    return nx, ux, lx
end
# ----------------------------------------------------------
# [1.c]  Training of neural network
# ----------------------------------------------------------
    mytrain(NN,data) = begin
        lossf(x,y) = Flux.mse(NN(x),y);
        pstrain = Flux.params(NN)
        Flux.@epochs 10 Flux.Optimise.train!(lossf, pstrain, data, Descent())
    end
# ----------------------------------------------------------
# [1.d]  Policy function conditional on expected values
# ----------------------------------------------------------
    update_solve(hat_vr, hat_vd, settings,params,uf) = begin
        # Starting the psolution of the model
        @unpack P, b,y = settings
        @unpack r, β, ne, nx, σrisk,θ = params
        p0 = findmin(abs.(0 .- b))[2]
        udef = repeat(settings.udef', ne, 1)
        hat_vf = max.(hat_vr,hat_vd)
        hat_D  = 1 * (hat_vd .> hat_vr)
        evf1 = hat_vf * P'
        evd1 = hat_vd * P'
        eδD1 = hat_D  * P'
        q1   = (1 / (1 + r)) * (1 .- eδD1) # price
        qb1  = q1 .* b
        βevf1= β*evf1
        vrnew = Array{Float64,2}(undef,ne,nx)
        cc1    = Array{Float64,2}(undef,ne,nx)
        bpnew = Array{CartesianIndex{2},2}(undef, ne, nx)
        yb    = b .+ y'
        @inbounds for i = 1:ne
            cc1 = yb[i, :]' .- qb1
            cc1 = max.(cc1,0)
            aux_u = uf.(cc1, σrisk) + βevf1
            vrnew[i, :], bpnew[i, :] = findmax(aux_u, dims = 1)
        end
        bb    = repeat(b, 1, nx)
        bb    = bb[bpnew]
        evaux = θ * evf1[p0, :]' .+  (1 - θ) * evd1
        vdnew = udef + β*evaux
        vfnew = max.(vrnew, vdnew)
        Dnew  = 1 * (vdnew .> vrnew)
        eδD   = Dnew  * P'
        qnew  = (1 / (1 + r)) * (1 .- eδD)
        return (vf = vfnew, vr = vrnew, vd = vdnew, D = Dnew, bb =  bb, q = qnew, bp = bpnew)
    end

############################################################
# [2] SETTING
############################################################
params = (r = 0.017,σrisk = 2.0, ρ = 0.945,η = 0.025, β = 0.953,θ = 0.282,nx = 21,m = 3, μ = 0.0,
        fhat = 0.969, ub = 0,lb = -0.4,tol = 1e-8, maxite = 500,ne = 251)
uf(x, σrisk) = x .^ (1 - σrisk) / (1 - σrisk)
hf(y, fhat) = min.(y, fhat * mean(y))

############################################################
# [3] THE MODEL
############################################################
# ----------------------------------------------------------
# [3.a] Solving the model
# ----------------------------------------------------------
polfun, settings = Solver(params, hf, uf);
MoDel = [vec(polfun[i]) for i = 1:6]
MoDel = [repeat(settings.b, params.nx) repeat(settings.y, inner = (params.ne, 1)) hcat(MoDel...)]
heads = [:debt, :output, :vf, :vr, :vd, :D, :b, :q]
ModelData = DataFrame(Tables.table(MoDel, header = heads))
# ----------------------------------------------------------
# [3.b] Plotting results from the Model
# ----------------------------------------------------------
set_default_plot_size(18cm, 12cm)
plots0 = Array{Any,1}(undef,6)
vars = ["vf" "vr" "vd" "b"]
titlevars = ["Value function" "Value of rapayment" "Value of dfefault" "Policy function for debt"]
for i in 1:length(vars)
    plots0[i] = Gadfly.plot(ModelData, x = "debt", y = vars[i], color = "output", Geom.line,
        Theme(background_color = "white",key_position = :right, key_title_font_size = 6pt, key_label_font_size = 6pt),
        Guide.ylabel("Value function"), Guide.xlabel("Debt (t)"), Guide.title(titlevars[i]))
end
draw(PNG("./Plots/ValuFunction.png"), plots0[1]);


set_default_plot_size(12cm, 8cm)
ytick = round.(settings.y, digits = 2)
yticks = [ytick[1], ytick[6], ytick[11], ytick[16], ytick[end]]
plots0[5] = Gadfly.plot( ModelData, x = "debt", y = "output", color = "D", Geom.rectbin,  Scale.color_discrete_manual("yellow", "black"),
        Theme(background_color = "white", key_title_font_size = 8pt, key_label_font_size = 8pt),
        Guide.ylabel("Output (t)"), Guide.xlabel("Debt (t)"), Guide.colorkey(title = "Default choice", labels = ["Default", "No Default"]),
        Guide.xticks(ticks = [-0.40, -0.3, -0.2, -0.1, 0]), Guide.yticks(ticks = yticks),  Guide.title("Default Choice"));
set_default_plot_size(18cm, 12cm)
h0 = Gadfly.gridstack([plots0[2] plots0[3]; plots0[4] plots0[5]])
draw(PNG("./Plots/Model0.png"), h0)

# ----------------------------------------------------------
# [3.c] Simulating data from  the model
# ----------------------------------------------------------
Nsim = 1000000
econsim0 = ModelSim(params, polfun, settings, hf, nsim = Nsim);
data0 = myunique(econsim0.sim)
DDsimulated = fill(NaN, params.ne * params.nx, 3)
DDsimulated[:, 1:2] = [repeat(settings.b, params.nx) repeat(settings.y, inner = (params.ne, 1))]
for i = 1:size(data0, 1)
    posb = findfirst(x -> x == data0[i, 2], settings.b)
    posy = findfirst(x -> x == data0[i, 8], settings.y)
    DDsimulated[(posy-1)*params.ne+posb, 3] = data0[i, 5]
end
heads = [:debt, :output, :D]
DDsimulated = DataFrame(Tables.table(DDsimulated, header = heads))
plots0[6] = Gadfly.plot(DDsimulated, x = "debt", y = "output", color = "D", Geom.rectbin, Scale.color_discrete_manual("white", "black", "yellow"),
    Theme(background_color = "white"), Theme(background_color = "white", key_title_font_size = 8pt, key_label_font_size = 8pt),
    Guide.ylabel("Output (t)"), Guide.xlabel("Debt (t)"), Guide.colorkey(title = "Default choice", labels = ["Non observed", "No Default", "Default"]),
    Guide.xticks(ticks = [-0.40, -0.3, -0.2, -0.1, 0]), Guide.yticks(ticks = yticks), Guide.title("Default choice: Simulated Data"));
pdef = round(100 * sum(econsim0.sim[:, 5]) / Nsim; digits = 2);
display("Simulation finished, with frequency of $pdef default events");

#= It gives us the first problems:
    □ The number of unique observations are small
    □ Some yellow whenm they shoul dbe black
 =#
set_default_plot_size(12cm, 12cm)
heat1 = Gadfly.vstack(plots0[5], plots0[6])
draw(PNG("./Plots/heat1.png"), heat1)

# **********************************************************
# [Note] To be sure that the updating code is well,
#       I input the actual value functions and verify the
#       deviations in policy functions
# **********************************************************
hat_vr = polfun.vr
hat_vd = polfun.vd
trial1 = update_solve(hat_vr, hat_vd, settings, params, uf)
difPolFun = max(maximum(abs.(trial1.bb - polfun.bb)), maximum(abs.(trial1.D - polfun.D)))
display("After updating the difference in Policy functions is : $difPolFun")
result = Array{Any,2}(undef,8,2) # [fit, residual]
# ##########################################################
# [4] FULL INFORMATION
# ##########################################################
cheby(x, d) = begin
    mat1 = Array{Float64,2}(undef, size(x, 1), d + 1)
    mat1[:, 1:2] = [ones(size(x, 1)) x]
    for i = 3:d+1
        mat1[:, i] = 2 .* x .* mat1[:, i-1] - mat1[:, i-1]
    end
    return mat1
end

myexpansion(vars::Tuple,d) = begin
    nvar = size(vars,1)
    auxi = vars[1]
    numi = convert(Array, 0:size(auxi,2)-1)'
    for i in 2:nvar
        n2v = size(auxi,2)
        auxi2 =  hcat([auxi[:,j] .* vars[i] for j in 1:n2v]...)
        numi2 =  hcat([numi[:,j] .+ convert(Array, 0:size(vars[i],2)-1)' for j in 1:n2v]...)
        auxi  = auxi2
        numi  = numi2
    end
    xbasis = vcat(numi,auxi)
    xbasis = xbasis[:,xbasis[1, :] .<=d]
    xbasis = xbasis[2:end,:]
    return xbasis
end

# ***************************************
# [4.a] Value of repayment
# ***************************************
ss = [repeat(settings.b, params.nx) repeat(settings.y, inner = (params.ne, 1))]
vr = vec(polfun.vr)
ssmin = minimum(ss, dims = 1)
ssmax = maximum(ss, dims = 1)
vrmin = minimum(vr)
vrmax = maximum(vr)
sst = 2 * (ss .- ssmin ) ./ (ssmax - ssmin) .- 1
vrt = 2 * (vr .- vrmin) ./ (vrmax- vrmin) .- 1
d = 4
# ∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘
# Approximating using a OLS approach
# ∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘
xs1 = [ones(params.nx * params.ne, 1) ss ss .^ 2 ss[:, 1] .* ss[:, 2]]  # bₜ, yₜ
β1  = (xs1' * xs1) \ (xs1' * vr)
result[1,1] = xs1 * β1
result[1,2] = vr - hat1
# ∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘
# Normal Basis
# ∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘
mat = (sst[:, 1] .^ convert(Array, 0:d)', sst[:, 2] .^ convert(Array, 0:d)')
xs2 = myexpansion(mat,d)
β2  = (xs2' * xs2) \ (xs2' * vrt)
result[2,1] = ((1 / 2 * ((xs2 * β2) .+ 1)) * (vrmax - vrmin) .+ vrmin)
result[2,2] = vr - result[2,1]
# ∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘
# Using Chebyshev Polynomials
# ∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘
mat = (cheby(sst[:, 1], d), cheby(sst[:, 2], d))
xs3 =  myexpansion(mat,d) # remember that it start at 0
β3  = (xs3' * xs3) \ (xs3' * vrt)
result[3,1] = ((1 / 2 * ((xs3 * β3) .+ 1)) * (vrmax - vrmin) .+ vrmin)
result[3,2] = vr - result[3,1]

# ∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘
# Neural Networks
# ∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘
dataux = repeat([sst vrt], 10, 1)
dataux = dataux[rand(1:size(dataux, 1), size(dataux, 1)), :]
traindata = Flux.Data.DataLoader((dataux[:, 1:2]', dataux[:, 3]'));


NNR1 = Chain(Dense(2, d, softplus), Dense(d, 1));
NNR2 = Chain(Dense(2, d, tanh), Dense(d, 1));
NNR3 = Chain(Dense(2, d, elu), Dense(d, 1));
NNR4 = Chain(Dense(2, d, sigmoid), Dense(d, 1));
NNR5 = Chain(Dense(2, d, swish), Dense(d, 1));

NeuralEsti(NN, data, x, y) = begin
    mytrain(NN, data)
    hatvrNN = ((1 / 2 * (NN(x')' .+ 1)) * (maximum(y) - minimum(y)) .+ minimum(y))
    resNN = y - hatvrNN
    return hatvrNN, resNN
end

result[4,1], result[4,2] = NeuralEsti(NNR1, traindata, sst, vr)
result[5,1], result[5,2] = NeuralEsti(NNR2, traindata, sst, vr)
result[6,1], result[6,2] = NeuralEsti(NNR3, traindata, sst, vr)
result[7,1], result[7,2] = NeuralEsti(NNR4, traindata, sst, vr)
result[8,1], result[8,2] = NeuralEsti(NNR5, traindata, sst, vr)

# ∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘
# Summarizing
# ∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘
sumR = Array{Float32,2}(undef,8,4)
f1(x)   = sqrt(mean(x .^ 2))
f2(x)   = maximum(abs.(x))
f3(x,y) = sqrt(mean((x ./ y) .^ 2))*100
f4(x,y) = maximum(abs.(x ./ y))*100
for i in 1:size(sumR,1)
    sumR[i,:] = [f1(result[i,2]) f2(result[i,2]) f3(result[i,2],vr) f4(result[i,2],vr)]
end

# ∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘
# Plotting approximations
# ∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘
heads = [:debt, :output, :VR1,:VR2,:VR3,:VR4,:VR5,:VR6,:VR7,:VR8, :Res1,:Res2,:Res3,:Res4,:Res5,:Res6,:Res7,:Res8]
modls = DataFrame(Tables.table([ss hcat(result...)],header = heads))
models= ["OLS" "Power series" "Chebyshev" "Softplus" "Tanh" "Elu" "Sigmoid" "Swish"]
plots1= Array{Any,2}(undef, 8,2) # [fit, residual]
for i = 1:8
    plots1[i,1] = Gadfly.plot(modls, x = "debt", y = heads[2+i], color = "output", Geom.line, Theme(background_color = "white",key_position = :none),
                            Guide.ylabel(""), Guide.title(models[i]) )
    plots1[i,2] = Gadfly.plot(modls,x = "debt",y = heads[10+i],color = "output",Geom.line, Theme(background_color = "white", key_position = :none),
                            Guide.ylabel(""), Guide.title(models[i]))
end
set_default_plot_size(24cm, 18cm)
plotfit1 = gridstack([plots0[2] plots1[1,1] plots1[2,1]; plots1[3,1] plots1[4,1] plots1[5,1]; plots1[6,1] plots1[7,1] plots1[8,1]])
plotres1 = gridstack([plots0[2] plots1[1,2] plots1[2,2]; plots1[3,2] plots1[4,2] plots1[5,2]; plots1[6,2] plots1[7,2] plots1[8,2]])
draw(PNG("./Plots/res1.png"), plotres1)
draw(PNG("./Plots/fit1.png"), plotfit1)

# ∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘
# Policy function conditional on fit
# ∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘
set_default_plot_size(24cm, 18cm)
polfunfit = Array{Any,1}(undef, 8)
simfit = Array{Any,1}(undef, 8)
difB = Array{Float64,2}(undef, params.ne * params.nx, 8)
PFB = Array{Float64,2}(undef, params.ne * params.nx, 8)
plotdifB = Array{Any,1}(undef, 8)
plotPFB = Array{Any,1}(undef, 8)
hat_vd = polfun.vd
nrep = 100000
for i = 1:8
    hat_vrfit = reshape(modls[:, 1+2*i], params.ne, params.nx)
    polfunfit[i] = update_solve(hat_vrfit, hat_vd, settings, params, uf)
    simfit[i] = ModelSim(params, polfunfit[i], settings, hf, nsim = nrep)
    global pdef = round(100 * sum(simfit[i].sim[:, 5]) / nrep; digits = 2)
    Derror = sum(abs.(polfunfit[i].D - polfun.D)) / (params.nx * params.ne)
    PFB[:, i] = vec(polfunfit[i].bb)
    difB[:, i] = vec(polfunfit[i].bb - polfun.bb)
    display("The model $i has $pdef percent of default and a default error choice of $Derror")
end
headsB = [:debt, :output, :Model1, :Model2, :Model3, :Model4, :Model5, :Model6, :Model7, :Model8]
DebtPoldif = DataFrame(Tables.table([ss difB], header = headsB))
DebtPol = DataFrame(Tables.table([ss PFB], header = headsB))

for i = 1:8
    plotdifB[i] = Gadfly.plot(
        DebtPoldif,
        x = "debt",
        y = headsB[2+i],
        color = "output",
        Geom.line,
        Theme(background_color = "white", key_position = :none),
        Guide.ylabel("Model " * string(i)),
        Guide.title("Error in PF model " * string(i)),
    )
    plotPFB[i] = Gadfly.plot(
        DebtPol,
        x = "debt",
        y = headsB[2+i],
        color = "output",
        Geom.line,
        Theme(background_color = "white", key_position = :none),
        Guide.ylabel("Model " * string(i)),
        Guide.title("Debt PF model " * string(i)),
    )
end

PFBerror = gridstack([
    p3 plotdifB[1] plotdifB[2]
    plotdifB[3] plotdifB[4] plotdifB[5]
    plotdifB[6] plotdifB[7] plotdifB[8]
])   #
draw(PNG("./Plots/PFBerror.png"), PFBerror)
plotPFB = gridstack([
    p3 plotPFB[1] plotPFB[2]
    plotPFB[3] plotPFB[4] plotPFB[5]
    plotPFB[6] plotPFB[7] plotPFB[8]
])
draw(PNG("./Plots/PFB.png"), plotPFB)


################################################################
# WITH SIMULATED DATA
################################################################
econsim = ModelSim(params, polfun, settings, hf, nsim = 100000);
ss1 = econsim.sim[:,2:3]
vr1 = econsim.sim[:,9]
ss1min = minimum(ss1, dims = 1)
ss1max = maximum(ss1, dims = 1)
vr1min = minimum(vr1)
vr1max = maximum(vr1)
sst1 = 2 * (ss1 .- ss1min ) ./ (ss1max - ss1min) .- 1
vrt1 = 2 * (vr1 .- vr1min) ./ (vr1max- vr1min) .- 1
d = 4
# ∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘
# Approximating using a OLS approach
# ∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘
xss1 = [ones(size(ss1,1)) ss1 ss1 .^ 2 ss1[:, 1] .* ss1[:, 2]]  # bₜ, yₜ
β1 = (xss1' * xss1) \ (xss1' * vr1)
hatvrols1 = xss1 * β1
res1s = vr1 - hatvrols1
# ∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘
# Normal Basis
# ∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘
mat1v = (sst1[:, 1] .^ convert(Array, 0:d)', sst1[:, 2] .^ convert(Array, 0:d)')
x1basis = myexpansion(mat1v,d)
β1basis = (x1basis' * x1basis) \ (x1basis' * vrt1)
hatvr1basis = ((1 / 2 * ((x1basis * β1basis) .+ 1)) * (vr1max - vr1min) .+ vr1min)
res2s = vr1 - hatvr1basis
# ∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘
# Using Chebyshev Polynomials
# ∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘
mat1v1 = (cheby(sst1[:, 1], d), cheby(sst1[:, 2], d))
x1cheby =  myexpansion(mat1v1,d) # remember that it start at 0
β1cheby = (x1cheby' * x1cheby) \ (x1cheby' * vrt1)
hatvr1cheby = ((1 / 2 * ((x1cheby * β1cheby) .+ 1)) * (vr1max - vr1min) .+ vr1min)
res3s = vr1 - hatvr1cheby

# ∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘
# Neural Networks
# ∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘
traindata = Flux.Data.DataLoader((sst1', vrt1'));


NNR1s = Chain(Dense(2, d, softplus), Dense(d, 1));
NNR2s = Chain(Dense(2, d, tanh), Dense(d, 1));
NNR3s = Chain(Dense(2, d, elu), Dense(d, 1));
NNR4s = Chain(Dense(2, d, sigmoid), Dense(d, 1));
NNR5s = Chain(Dense(2, d, swish), Dense(d, 1));

hatvrNNR1s, resNN1s = NeuralEsti(NNR1s, traindata, sst1, vr1)
hatvrNNR2s, resNN2s = NeuralEsti(NNR2s, traindata, sst1, vr1)
hatvrNNR3s, resNN3s = NeuralEsti(NNR3s, traindata, sst1, vr1)
hatvrNNR4s, resNN4s = NeuralEsti(NNR4s, traindata, sst1, vr1)
hatvrNNR5s, resNN5s = NeuralEsti(NNR5s, traindata, sst1, vr1)
# ∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘
# Plotting approximations
# ∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘
heads = [:debt, :output, :VRMod1,:ResMod1,:VRMod2, :ResMod2,:VRMod3,:ResMod3,:VRMod4,:ResMod4,:VRMod5,
    :ResMod5,:VRMod6,:ResMod6,:VRMod7,:ResMod7, :VRMod8,:ResMod8]
modlsS = DataFrame(Tables.table(
    [ss1 hatvrols1 res1s hatvr1basis res2s hatvr1cheby res3s hatvrNNR1s resNN1s hatvrNNR2s resNN2s hatvrNNR3s resNN3s hatvrNNR4s resNN4s hatvrNNR5s resNN5s],
    header = heads,
))

plotresS = Array{Any,1}(undef, 8)
plotfitS = Array{Any,1}(undef, 8)
for i = 1:8
    if i == 1
        plotresS[i] = Gadfly.plot(
            modlsS,
            x = "debt",
            y = heads[2+2*i],
            color = "output",
            Geom.line,
            Theme(background_color = "white"),
            Guide.ylabel("Model 1"),
            Guide.title("Residuals model " * string(i)),
        )
        plotfitS[i] = Gadfly.plot(
            modlsS,
            x = "debt",
            y = heads[1+2*i],
            color = "output",
            Geom.line,
            Theme(background_color = "white", key_position = :none),
            Guide.ylabel("Model " * string(i)),
            Guide.title("Fit model " * string(i)),
        )
    else
        plotresS[i] = Gadfly.plot(
            modlsS,
            x = "debt",
            y = heads[2+2*i],
            color = "output",
            Geom.line,
            Theme(background_color = "white", key_position = :none),
            Guide.ylabel("Model " * string(i)),
            Guide.title("Residuals model " * string(i)),
        )
        plotfitS[i] = Gadfly.plot(
            modlsS,
            x = "debt",
            y = heads[1+2*i],
            color = "output",
            Geom.line,
            Theme(background_color = "white", key_position = :none),
            Guide.ylabel("Model " * string(i)),
            Guide.title("Fit model " * string(i)),
        )
    end
end
set_default_plot_size(24cm, 18cm)
plotres1S = gridstack([
    p1 plotresS[1] plotresS[2]
    plotresS[3] plotresS[4] plotresS[5]
    plotresS[6] plotresS[7] plotresS[8]
])
draw(PNG("./Plots/res1S.png"), plotres1S)
plotfit1S = gridstack([
    p1 plotfitS[1] plotfitS[2]
    plotfitS[3] plotfitS[4] plotfitS[5]
    plotfitS[6] plotfitS[7] plotfitS[8]
])
draw(PNG("./Plots/fit1S.png"), plotfit1S)

# ∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘
# Policy function conditional on fit
# ∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘∘
set_default_plot_size(24cm, 18cm)
polfunfit = Array{Any,1}(undef, 8)
simfit = Array{Any,1}(undef, 8)
difB = Array{Float64,2}(undef, params.ne * params.nx, 8)
PFB = Array{Float64,2}(undef, params.ne * params.nx, 8)
plotdifB = Array{Any,1}(undef, 8)
plotPFB = Array{Any,1}(undef, 8)
hat_vd = polfun.vd
nrep = 100000
for i = 1:8
    hat_vrfit = reshape(modls[:, 1+2*i], params.ne, params.nx)
    polfunfit[i] = update_solve(hat_vrfit, hat_vd, settings, params, uf)
    simfit[i] = ModelSim(params, polfunfit[i], settings, hf, nsim = nrep)
    global pdef = round(100 * sum(simfit[i].sim[:, 5]) / nrep; digits = 2)
    Derror = sum(abs.(polfunfit[i].D - polfun.D)) / (params.nx * params.ne)
    PFB[:, i] = vec(polfunfit[i].bb)
    difB[:, i] = vec(polfunfit[i].bb - polfun.bb)
    display("The model $i has $pdef percent of default and a default error choice of $Derror")
end
headsB =
    [:debt, :output, :Model1, :Model2, :Model3, :Model4, :Model5, :Model6, :Model7, :Model8]
DebtPoldif = DataFrame(Tables.table([ss difB], header = headsB))
DebtPol = DataFrame(Tables.table([ss PFB], header = headsB))

for i = 1:8
    plotdifB[i] = Gadfly.plot(
        DebtPoldif,
        x = "debt",
        y = headsB[2+i],
        color = "output",
        Geom.line,
        Theme(background_color = "white", key_position = :none),
        Guide.ylabel("Model " * string(i)),
        Guide.title("Error in PF model " * string(i)),
    )
    plotPFB[i] = Gadfly.plot(
        DebtPol,
        x = "debt",
        y = headsB[2+i],
        color = "output",
        Geom.line,
        Theme(background_color = "white", key_position = :none),
        Guide.ylabel("Model " * string(i)),
        Guide.title("Debt PF model " * string(i)),
    )
end

PFBerror = gridstack([
    p3 plotdifB[1] plotdifB[2]
    plotdifB[3] plotdifB[4] plotdifB[5]
    plotdifB[6] plotdifB[7] plotdifB[8]
])   #
draw(PNG("./Plots/PFBerror.png"), PFBerror)
plotPFB = gridstack([
    p3 plotPFB[1] plotPFB[2]
    plotPFB[3] plotPFB[4] plotPFB[5]
    plotPFB[6] plotPFB[7] plotPFB[8]
])
draw(PNG("./Plots/PFB.png"), plotPFB)

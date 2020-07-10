###############################################################################
# [-] CODES FOR CONVERGENCE MODEL - NN - MODEL
###############################################################################

function convergence(VNDhat, VDhat, PolFun, Params, Ext, uf, tburn)
   #=
      It is the algorithm to find a convergence between neural networks
      and a Default Economy. The steps for that are:
      [1] As we have two set of Θₕ , where h={No Default, Default}
         the total size for the simulation is the sum of both size
      [2] Set both neural networks settings
         * ΨnD -> Parameters in No Default >> NetworkND is the NN
         * ψD  -> Parameters in Default    >> NetworkD  is the NN
      [3] Solve the model (see the function SolverCon)
      [4] Make a new simulation
      [5] Updating the neural networks
         *[5.1] Divide the data in No Default and Default
               >> normalize >> Train

         *[5.2] Update the structure and parameters
      [Re Do]
   =#
   # ===========================================================================
   # (1) Settings: We unpack some requirements
   mytup = _unpack(Params, Ext, uf);
   tsim  = length(VNDhat.Hat) + length(VDhat.Hat);

   # ===========================================================================
   # (2) Defining Neural Networks structure
   ϕf(x) = log1p(exp(x));

   # (2.1) No Default events
   ψnD, modnD= Flux.destructure(VNDhat.Mhat);
   ψnDold    = ψnD;
   NetWorkND = modnD(ψnD);
   ΨnD       = Flux.params(NetWorkND);
   Lnd(x, y) = Flux.mse(NetWorkND(x), y);

   # (2.1) Default events
   ψD, modD = Flux.destructure(VDhat.Mhat);
   ψDold    = ψD;
   NetWorkD = modD(ψD);
   ΨD       = Flux.params(NetWorkD);
   Ld(x, y) = Flux.mse(NetWorkD(x), y);

   # ===========================================================================
   # (3) Iteration for convergence

   DataND   = VNDhat.Data;
   DataD    = VDhat.Data;
   repli    = 1;
   PolFun1  = nothing;
   EconSim1 = nothing;
   difΨ     = 1;
   difΨ1    = 1;
   difΨ2    = 1;
   value    = 0
   while difΨ > 1e-8 && repli < 400
      # ========================================================================
      # (3.1) New Solution for the model, see function
      PolFun1 = SolverCon(DataND, NetWorkND, DataD, NetWorkD, mytup);

      # ========================================================================
      # (3.2) New Simulation >> could have reduce grid
      EconSim1 =
            DefEcon.ModelSim(Params, PolFun1, Ext, nsim = tsim, burn = tburn);
      # ========================================================================
      # (3.3) Updating of the Neural Network

      # (3.3.1) Raw data
      vf = EconSim1.Sim[:, 6];
      st = EconSim1.Sim[:, 2:3];
      defstatus =  EconSim1.Sim[:, 5];

      # (3.3.2) Training No Default Neural Network
      vnd = vf[defstatus .== 0];
      snd = st[defstatus .== 0, :];
      Ynd = DefEcon.mynorm(vnd);
      Snd = DefEcon.mynorm(snd);
      dataND = Flux.Data.DataLoader(Snd', Ynd');
      Flux.Optimise.train!(Lnd, ΨnD, dataND, Descent()); # Now Ψ is updated

      # (3.3.3) Training Default Neural Network
      vd = vf[defstatus .== 1]
      sd = st[defstatus .== 1, :]
      Yd = DefEcon.mynorm(vd);
      Sd = DefEcon.mynorm(sd);
      dataD = Flux.Data.DataLoader(Sd', Yd');
      Flux.Optimise.train!(Ld, ΨD, dataD, Descent()); # Now Ψ is updated

      # ========================================================================
      # (3.4) Updating for new round

      # (3.4.1) No Default Neural Network
      ψnD, modnD = Flux.destructure(NetWorkND);
      ψnD  = 0.9 * ψnD + 0.1 * ψnDold;
      difΨ1= maximum(abs.(ψnD - ψnDold));
      ψnDold    = ψnD;
      NetWorkND = modnD(ψnD);
      ΨnD       = Flux.params(NetWorkND);
      Lnd(x, y) = Flux.mse(NetWorkND(x), y);
      DataND    = (vnd, snd);

      # (3.4.1) No Default Neural Network

      ψD, modD = Flux.destructure(NetWorkD);
      ψD    = 0.9 * ψD + 0.1 * ψDold;
      difΨ2 = maximum(abs.(ψD - ψDold));
      ψDold    = ψD;
      NetWorkD = modD(ψD);
      ΨD       = Flux.params(NetWorkD);
      Ld(x, y) = Flux.mse(NetWorkD(x), y);
      DataD    = (vd, sd);

      # ========================================================================
      if flagcont
         difΨ  = max(difΨ1,difΨ2);
         NDefaults = sum(defstatus);
         PorcDef = 100*NDefaults / tsim;
         display("Iteration $repli: with a difference of $difΨ")
         display("with a dif. $difΨ1 for No-Default, $difΨ2 for Default")
         display("Number of default events: $NDefaults");
      end
      repli += 1;
   end
   if difΨ>1e-8
      display("Convergence not achieved")
   end
   return PolFun1, EconSim1;
end

function SolverCon(DataND, NetWorkND, DataD, NetWorkD, mytup)
   @unpack σrisk, bgrid, ygrid, nx, ne, P, ydef,
      udef, yb, BB, p0, stateND, stateD, utf, β, r, θ = mytup
   #=
   Note: To calculate the the expected value we will follow next steps:
      1. Let Θₕ be the vector of parameters estimated in the Neural Network
         for h = {No Default, Default};
      2. As in every case, I previously normalized them with the formula
         ̃x = [x - 1/2 (max(x) + min(x))]/(1/2 (max(x) - min(x))),
         I get the maximum value from each one: states (sₕ), values (vₕ).
         Let x₀ₕ represents the variable x in for h-choice in the initial
         normalization
      3. Then, I apply the same normalization with the states from the grid
         ̃x₁ₕ =  [x₁ - 1/2 (max(x₀ₕ) + min(x₀ₕ))]/(1/2 (max(x₀ₕ) - min(x₀ₕ)))
         this allow me to have the grid values in the same scale than the
         inputs for the neural network
      4. Later I predict Vₕ in each case conditional on the grid,
      5. Convert the new prediction ̂y₁ₕ using the extremums in for y₀ₕ
         and calculate the expected using the markov matrix
   =#

   # ===========================================================================
   # [1] Expected Value of Continuation:
   #        hat >> inverse normalization >> matrix form >> E[]
   maxVND, minVND = (maximum(DataND[1]),minimum(DataND[1]));
   maxsND, minsND = (maximum(DataND[2], dims = 1),minimum(DataND[2], dims = 1));
   staN_nD = (stateND .- 0.5 * (maxsND + minsND)) ./ (0.5 * (maxsND - minsND));
   vc = NetWorkND(staN_nD');
   vc = (0.5 * (maxVND - minVND) * vc) .+ 0.5 * (maxVND + minVND);
   VC = reshape(vc, ne, nx);
   EVC = VC * P';  # Expected value of no defaulting

   # ===========================================================================
   # [2] Expected Value of Default:
   #        hat >> inverse normalization >> matrix form >> E[]
   maxVD, minVD = (maximum(DataD[1]),minimum(DataD[1]));
   maxsD, minsD = (maximum(DataD[2], dims = 1),minimum(DataD[2], dims = 1));
   staN_D  = (stateD .- 0.5 * (maxsD + minsD)) ./ (0.5 * (maxsD - minsD));
   vd = NetWorkD(staN_D');
   vd = (0.5 * (maxVD - minVD) * vd) .+ 0.5 * (maxVD + minVD);
   VD = reshape(vd, ne, nx);
   EVD = VD * P'; # expected value of being in default in the next period

   # [1.6] Income by issuing bonds
   #q  = EconSol.Sol.BPrice;
   D = 1 * (VD .> VC);
   q = (1 / (1 + r)) * (1 .- (D * P'));
   qB = q .* bgrid;

   # [1.7] Policy function for bonds under continuation
   βEV = β * EVC;
   VC1 = Array{Float64,2}(undef, ne, nx);
   Bindex = Array{CartesianIndex{2},2}(undef, ne, nx);
   @inbounds for i = 1:ne
      cc = yb[i, :]' .- qB;
      cc[cc.<0] .= 0;
      aux_u = utf.(cc, σrisk) + βEV;
      VC1[i, :], Bindex[i, :] = findmax(aux_u, dims = 1);
   end
   B1 = BB[Bindex];

   # [1.8] Value function of default
   βθEVC0 = β * θ * EVC[p0, :];
   VD1 = βθEVC0' .+ (udef' .+ β * (1 - θ) * EVD);

   # --------------------------------------------------------------
   # [1.9]. New Continuation Value, Default choice, price
   VF1 = max.(VC1, VD1);
   D1 = 1 * (VD1 .> VC1);
   q1 = (1 / (1 + r)) * (1 .- (D1 * P'));
   PolFun1 = (VF = VF1, VC = VC1, VD = VD1, D = D1, BP = B1, Price = q1);
   return PolFun1;
end

function _unpack(Params, Ext, uf)
   @unpack r, β, θ, σrisk = Params
   @unpack bgrid, ygrid, ydef, P = Ext
   nx = length(ygrid)
   ne = length(bgrid)
   yb = bgrid .+ ygrid'
   BB = repeat(bgrid, 1, nx)
   p0 = findmin(abs.(0 .- bgrid))[2]
   stateND= [repeat(bgrid, nx, 1) repeat(ygrid, inner = (ne, 1))]
   stateD = [repeat(bgrid, nx, 1) repeat(ydef, inner = (ne, 1))]
   #stateD = [zeros(ne*nx) repeat(ydef, inner = (ne, 1))]
   udef = uf.(ydef, σrisk)
   mytup = (
      r = r, β = β, θ = θ, σrisk = σrisk, bgrid = bgrid,
      ygrid = ygrid, nx = nx,  ne = ne,  P = P, ydef = ydef,
      udef = udef,  yb = yb, BB = BB, p0 = p0, stateND = stateND,
      stateD = stateD, utf = uf,
   )
   return mytup;
end

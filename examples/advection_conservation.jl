#--------------------------------Markdown Language Header-----------------------
# # Advection Equation Example: Conservation Form
#
#
# ![](advection2d.png)
#-
#
#-
# ## Introduction
#
# This example shows how to solve the Advection equation in conservation form for 1D and 2D.
#
# ## Continuous Governing Equations
# We solve the following equation:
#
# ```math
# \frac{\partial \rho}{\partial t} + \nabla \cdot \mathbf{U} = 0 \; \; (1)
# ```
# where $\mathbf{u}=(u,v)$ depending on how many spatial dimensions we are using, and $\mathbf{U}=\rho \mathbf{u},
# We employ periodic boundary conditions across all four walls of the square domain.
#
#-
# ## Discontinous Galerkin Method
# To solve Eq. (1) in one, two, and three dimensions we use the Discontinuous Galerkin method with basis functions comprised of tensor products
# of one-dimensional Lagrange polynomials based on Lobatto points. Multiplying Eq. (1) by a test function $\psi$ and integrating within each element $\Omega_e$ such that $\Omega = \bigcup_{e=1}^{N_e} \Omega_e$ we get
#
# ```math
# \int_{\Omega_e} \psi \frac{\partial \rho^{(e)}_N}{\partial t} d\Omega_e + \int_{\Omega_e} \psi \nabla \cdot \mathbf{f}^{(e)}_N d\Omega_e =  0 \; \; (2)
# ```
# where $\mathbf{q}^{(e)}_N=\sum_{i=1}^{(N+1)^{dim}} \psi_i(\mathbf{x}) \mathbf{q}_i(t)$ is the finite dimensional expansion with basis functions $\psi(\mathbf{x})$, where $\mathbf{q}=\left( h, \mathbf{U}^T \right)^T$ and
# ```math
# \mathbf{f}=\left( \mathbf{U}, \frac{\mathbf{U} \otimes \mathbf{U}}{h} + g (h^2 - h^2_b) \mathbf{I}_2 \right).
# ```
# Integrating Eq. (2) by parts yields
#
# ```math
# \int_{\Omega_e} \psi \frac{\partial \rho}^{(e)}_N}{\partial t} d\Omega_e + \int_{\Gamma_e} \psi \mathbf{n} \cdot \mathbf{f}^{(*,e)}_N d\Gamma_e - \int_{\Omega_e} \nabla \psi \cdot \mathbf{f}^{(e)}_N d\Omega_e = 0 \; \; (3)
# ```
#
# where the second term on the left denotes the flux integral term (computed in "function fluxrhs") and the third term denotes the volume integral term (computed in "function volumerhs").  The superscript $(*,e)$ in the flux integral term denotes the numerical flux. Here we use the Rusanov flux.
#
#-
# ## Commented Program
#
#--------------------------------Markdown Language Header-----------------------

# ### Define Input parameters:
# N is polynomial order and
# brickN(Ne) generates a brick-grid with Ne elements in each direction
N = 4 #polynomial order
brickN = (10) #1D brickmesh
#brickN = (1 * 12, 1 * 12) #2D brickmesh
#brickN = (10, 10) #2D brickmesh
#brickN = (10, 10, 10) #3D brickmesh
DFloat = Float64 #Number Type
tend = DFloat(1.0) #Final Time

# ### Load the MPI and Canary packages where Canary builds the mesh, generates basis functions, and metric terms.
using MPI
using Canary
using Printf: @sprintf

# ### The grid that we create determines the number of spatial dimensions that we are going to use.
dim = length(brickN)

# ###Output the polynomial order, space dimensions, and element configuration
println("N= ",N)
println("dim= ",dim)
println("brickN= ",brickN)
println("DFloat= ",DFloat)

# ### Initialize MPI and get the communicator, rank, and size
MPI.Initialized() || MPI.Init() # only initialize MPI if not initialized
MPI.finalize_atexit()
mpicomm = MPI.COMM_WORLD
mpirank = MPI.Comm_rank(mpicomm)
mpisize = MPI.Comm_size(mpicomm)

# ### Generate a local view of a fully periodic Cartesian mesh.
if dim == 1
  (Nx, ) = brickN
  local x = range(DFloat(0); length=Nx+1, stop=1)
  mesh = brickmesh((x, ), (true, ); part=mpirank+1, numparts=mpisize)
elseif dim == 2
  (Nx, Ny) = brickN
  local x = range(DFloat(0); length=Nx+1, stop=1)
  local y = range(DFloat(0); length=Ny+1, stop=1)
  mesh = brickmesh((x, y), (true, true); part=mpirank+1, numparts=mpisize)
else
  (Nx, Ny, Nz) = brickN
  local x = range(DFloat(0); length=Nx+1, stop=1)
  local y = range(DFloat(0); length=Ny+1, stop=1)
  local z = range(DFloat(0); length=Nz+1, stop=1)
  mesh = brickmesh((x, y, z), (true, true, true); part=mpirank+1, numparts=mpisize)
end

# ### Partition the mesh using a Hilbert curve based partitioning
mesh = partition(mpicomm, mesh...)

# ### Connect the mesh in parallel
mesh = connectmesh(mpicomm, mesh...)

# ### Get the degrees of freedom along the faces of each element.
# vmap(:,f,e) gives the list of local (mpirank) points for the face "f" of element "e".  vmapP points to the outward (or neighbor) element and vmapM for the current element. P=+ or right and M=- or left.
(vmapM, vmapP) = mappings(N, mesh.elemtoelem, mesh.elemtoface, mesh.elemtoordr)

# ### Create 1-D operators
# $\xi$ and $\omega$ are the 1D Lobatto points and weights and $D$ is the derivative of the basis function.
(ξ, ω) = lglpoints(DFloat, N)
D = spectralderivative(ξ)

# ### Compute metric terms
# nface and nelem refers to the total number of faces and elements for this MPI rank. Also, coord contains the dim-tuple coordinates in the mesh.
(nface, nelem) = size(mesh.elemtoelem)
coord = creategrid(Val(dim), mesh.elemtocoord, ξ)
if dim == 1
  x = coord.x
  for j = 1:length(x)
    x[j] = x[j]
  end
elseif dim == 2
  (x, y) = (coord.x, coord.y)
  for j = 1:length(x)
    (x[j], y[j]) = (x[j] .+ sin.(π * x[j]) .* sin.(2 * π * y[j]) / 10,
                    y[j] .+ sin.(2 * π * x[j]) .* sin.(π * y[j]) / 10)
  end
elseif dim == 3
  (x, y, z) = (coord.x, coord.y, coord.z)
  for j = 1:length(x)
    (x[j], y[j], z[j]) = (x[j] + (sin(π * x[j]) * sin(2 * π * y[j]) *
                                  cos(2 * π * z[j])) / 10,
                          y[j] + (sin(π * y[j]) * sin(2 * π * x[j]) *
                                  cos(2 * π * z[j])) / 10,
                          z[j] + (sin(π * z[j]) * sin(2 * π * x[j]) *
                                  cos(2 * π * y[j])) / 10)
  end
end

# ### First VTK Call
# This first VTK call dumps the mesh out for all mpiranks.
include("vtk.jl")
writemesh(@sprintf("SWE%dD_rank_%04d_mesh", dim, mpirank), coord...;
          realelems=mesh.realelems)

# ### Compute the metric terms
# This call computes the metric terms of the grid such as $\xi_\mathbf{x}$, $\eta_\mathbf{x}$, $\zeta_\mathbf{x}$ for all spatial dimensions $\mathbf{x}$ depending on the dimension of $dim$.
metric = computemetric(coord..., D)

# ### Generate the State Vectors
# We need to create as many velocity vectors as there are dimensions.
if dim == 1
  statesyms = (:ρ, :U)
elseif dim == 2
  statesyms = (:ρ, :U, :V)
elseif dim == 3
  statesyms = (:ρ, :U, :V, :W)
end

# ### Create storage for state vector and right-hand side
# Q holds the solution vector and rhs the rhs-vector which are dim+1 tuples
# In addition, here we generate the initial conditions
Q   = NamedTuple{statesyms}(ntuple(j->zero(coord.x), length(statesyms)))
rhs = NamedTuple{statesyms}(ntuple(j->zero(coord.x), length(statesyms)))
if dim == 1
  Q.ρ .= sin.(2 * π * x) .+ 2.0
  Q.U .= Q.ρ .* (1.0)
elseif dim == 2
  Q.ρ .= sin.(2 * π * x) .* sin.(2 *  π * y) .+ 2.0
  Q.U .= Q.ρ .* (1.0)
  Q.V .= Q.ρ .* (1.0)
elseif dim == 3
  Q.ρ .= sin.(2 * π * x) .* sin.(2 *  π * y) .* sin.(2 * π * z) .+ 2.0
#  Q.ρ .= sin.(2 * π * x) .* sin.(2 *  π * y) .+ 2.0
  Q.U .= Q.ρ .* (1.0)
  Q.V .= Q.ρ .* (1.0)
  Q.W .= Q.ρ .* (1.0)
end

# ### Compute the time-step size and number of time-steps
# Compute a $\Delta t$ such that the Courant number is $1$.
# This is done for each mpirank and then we do an MPI_Allreduce to find the global minimum.
dt = [floatmax(DFloat)]
if dim == 1
    (ξx) = (metric.rx)
    (ρ,U) = (Q.ρ,Q.U)
    for n = 1:length(U)
        loc_dt = (2ρ[n])  ./ (abs.(U[n] * ξx[n]))
        dt[1] = min(dt[1], loc_dt)
    end
elseif dim == 2
    (ξx, ξy, ηx, ηy) = (metric.rx, metric.ry, metric.sx, metric.sy)
    (ρ,U,V) = (Q.ρ,Q.U,Q.V)
    for n = 1:length(U)
        loc_dt = (2ρ[n]) ./ max(abs.(U[n] * ξx[n] + V[n] * ξy[n]),
                          abs.(U[n] * ηx[n] + V[n] * ηy[n]))
        dt[1] = min(dt[1], loc_dt)
    end
elseif dim == 3
    (ξx, ξy, ξz) = (metric.rx, metric.ry, metric.rz)
    (ηx, ηy, ηz) = (metric.sx, metric.sy, metric.sz)
    (ζx, ζy, ζz) = (metric.tx, metric.ty, metric.tz)
    (ρ,U,V,W) = (Q.ρ,Q.U,Q.V,Q.W)
    for n = 1:length(U)
        loc_dt = (2ρ[n]) ./ max(abs.(U[n] * ξx[n] + V[n] * ξy[n] + W[n] * ξz[n]),
                          abs.(U[n] * ηx[n] + V[n] * ηy[n] + W[n] * ηz[n]),
                          abs.(U[n] * ζx[n] + V[n] * ζy[n] + W[n] * ζz[n]))
        dt[1] = min(dt[1], loc_dt)
    end
end
dt = MPI.Allreduce(dt[1], MPI.MIN, mpicomm)
dt = DFloat(dt / N^sqrt(2))
nsteps = ceil(Int64, tend / dt)
dt = tend / nsteps
@show (dt, nsteps)

# ### Compute the exact solution at the final time.
# Later Δ will be used to store the difference between the exact and computed solutions.
Δ   = NamedTuple{statesyms}(ntuple(j->zero(coord.x), length(statesyms)))
if dim == 1
  u = Q.U ./ Q.ρ
  Δ.ρ .= sin.(2 * π * (x - tend * u)) .+ 2
  Δ.U .=  Q.U
elseif dim == 2
  u = Q.U ./ Q.ρ
  v = Q.V ./ Q.ρ
  Δ.ρ .= sin.(2 * π * (x - tend * u)) .* sin.(2 *  π * (y - tend * v)) .+ 2
  Δ.U .=  Q.U
  Δ.V .=  Q.V
elseif dim == 3
  u = Q.U ./ Q.ρ
  v = Q.V ./ Q.ρ
  w = Q.W ./ Q.ρ
  Δ.ρ .= sin.(2 * π * (x - tend * u)) .* sin.(2 *  π * (y - tend * v)) .*
         sin.(2 * π * (z - tend * w)) .+ 2
  #Δ.ρ .= sin.(2 * π * (x - tend * u)) .* sin.(2 *  π * (y - tend * v)) .+ 2
  Δ.U .=  Q.U
  Δ.V .=  Q.V
  Δ.W .=  Q.W
end

# ### Store Explicit RK Time-stepping Coefficients
# We use the fourth-order, low-storage, Runge–Kutta scheme of Carpenter and Kennedy (1994)
# ((5,4) 2N-Storage RK scheme.
#
# Ref:
# @TECHREPORT{CarpenterKennedy1994,
#   author = {M.~H. Carpenter and C.~A. Kennedy},
#   title = {Fourth-order {2N-storage} {Runge-Kutta} schemes},
#   institution = {National Aeronautics and Space Administration},
#   year = {1994},
#   number = {NASA TM-109112},
#   address = {Langley Research Center, Hampton, VA},
# }
RKA = (DFloat(0),
       DFloat(-567301805773)  / DFloat(1357537059087),
       DFloat(-2404267990393) / DFloat(2016746695238),
       DFloat(-3550918686646) / DFloat(2091501179385),
       DFloat(-1275806237668) / DFloat(842570457699 ))

RKB = (DFloat(1432997174477) / DFloat(9575080441755 ),
       DFloat(5161836677717) / DFloat(13612068292357),
       DFloat(1720146321549) / DFloat(2090206949498 ),
       DFloat(3134564353537) / DFloat(4481467310338 ),
       DFloat(2277821191437) / DFloat(14882151754819))

RKC = (DFloat(0),
       DFloat(1432997174477) / DFloat(9575080441755),
       DFloat(2526269341429) / DFloat(6820363962896),
       DFloat(2006345519317) / DFloat(3224310063776),
       DFloat(2802321613138) / DFloat(2924317926251))

#-------------------------------------------------------------------------------#
#-----Begin Volume, Flux, Update, and Error Functions for Multiple Dispatch-----#
#-------------------------------------------------------------------------------#
# ### Volume RHS Routines
# These functions solve the volume term $\int_{\Omega_e} \nabla \psi \cdot \left( \rho \mathbf{u} \right)^{(e)}_N$ for:
# Volume RHS for 1D
function volumerhs!(rhs, Q::NamedTuple{S, NTuple{2, T}}, metric, D, ω,
                    elems) where {S, T}
  rhsρ = rhs.ρ
  (ρ, U) = (Q.ρ, Q.U)
  Nq = size(ρ, 1)
  J = metric.J
  ξx = metric.rx
  for e ∈ elems
      # loop of ξ-grid lines
      rhsρ[:,e] += D' * (ω .* J[:,e] .* (ξx[:,e] .* U[:,e]))
  end #e ∈ elems
end #function volumerhs-1d

# Volume RHS for 2D
function volumerhs!(rhs, Q::NamedTuple{S, NTuple{3, T}}, metric, D, ω,
                    elems) where {S, T}
    rhsρ = rhs.ρ
    (ρ, U, V) = (Q.ρ, Q.U, Q.V)
    Nq = size(ρ, 1)
    J = metric.J
    (ξx, ηx, ξy, ηy) = (metric.rx, metric.sx, metric.ry, metric.sy)
    for e ∈ elems
        # loop of ξ-grid lines
        for j = 1:Nq
            rhsρ[:, j, e] +=
                D' * (ω[j] * ω .* J[:, j, e].* (ξx[:, j, e] .* U[:, j, e] + ξy[:, j, e] .* V[:, j, e]))
        end #j
        # loop of η-grid lines
        for i = 1:Nq
            rhsρ[i, :, e] +=
                D' * (ω[i] * ω .* J[i, :, e].* (ηx[i, :, e] .* U[i, :, e] + ηy[i, :, e] .* V[i, :, e]))
        end #i
    end #e ∈ elems
end #function volumerhs-2d

# Volume RHS for 3D
function volumerhs!(rhs, Q::NamedTuple{S, NTuple{4, T}}, metric, D, ω,
                    elems) where {S, T}
    rhsρ = rhs.ρ
    (ρ, U, V, W) = (Q.ρ, Q.U, Q.V, Q.W)
    Nq = size(ρ, 1)
    J = metric.J
    (ξx, ηx, ζx) = (metric.rx, metric.sx, metric.tx)
    (ξy, ηy, ζy) = (metric.ry, metric.sy, metric.ty)
    (ξz, ηz, ζz) = (metric.rz, metric.sz, metric.tz)
    for e ∈ elems
        # loop of ξ-grid lines
        for k = 1:Nq
            for j = 1:Nq
                rhsρ[:, j, k, e] +=
                    D' * (ω[j] * ω[k] * ω .* J[:, j, k, e] .*
                          (ξx[:, j, k, e] .* U[:, j, k, e] +
                           ξy[:, j, k, e] .* V[:, j, k, e] +
                           ξz[:, j, k, e] .* W[:, j, k, e]))
            end #j
        end #k
        # loop of η-grid lines
        for k = 1:Nq
            for i = 1:Nq
                rhsρ[i, :, k, e] +=
                    D' * (ω[i] * ω[k] * ω .* J[i, :, k, e] .*
                          (ηx[i, :, k, e] .* U[i, :, k, e] +
                           ηy[i, :, k, e] .* V[i, :, k, e] +
                           ηz[i, :, k, e] .* W[i, :, k, e]))
            end #i
        end #k
        # loop of ζ-grid lines
        for j = 1:Nq
            for i = 1:Nq
                rhsρ[i, j, :, e] +=
                    D' * (ω[i] * ω[j] * ω .* J[i, j, :, e] .*
                          (ζx[i, j, :, e] .* U[i, j, :, e] +
                           ζy[i, j, :, e] .* V[i, j, :, e] +
                           ζz[i, j, :, e] .* W[i, j, :, e]))
            end #i
        end #j
    end #e ∈ elems
end

# ### Flux RHS Routines
# These functions solve the flux integral term $\int_{\Gamma_e} \psi \mathbf{n} \cdot \left( \rho \mathbf{u} \right)^{(*,e)}_N$ for:
# Flux RHS for 1D
function fluxrhs!(rhs, Q::NamedTuple{S, NTuple{2, T}}, metric, ω, elems, vmapM,
                  vmapP) where {S, T}
    rhsρ = rhs.ρ
    (ρ, U) = (Q.ρ, Q.U)
    nface = 2
    (nx, sJ) = (metric.nx, metric.sJ)
    nx = reshape(nx, size(vmapM))
    sJ = reshape(sJ, size(vmapM))

    for e ∈ elems
        for f ∈ 1:nface
            ρM = ρ[vmapM[1, f, e]]
            uM = U[vmapM[1, f, e]] ./ ρM
            fM = ρM .* uM

            ρP = ρ[vmapP[1, f, e]]
            uP = U[vmapP[1, f, e]] ./ ρP
            fP = ρP .* uP

            nxM = nx[1, f, e]
            λ = max.(abs.(nxM .* uM), abs.(nxM .* uP))

            F = (nxM .* (fM + fP) - λ .* (ρP - ρM)) / 2
            rhsρ[vmapM[1, f, e]] -= sJ[1, f, e] .* F
        end #for f ∈ 1:nface
    end #e ∈ elems
end #function fluxrhs-1d

# Flux RHS for 2D
function fluxrhs!(rhs, Q::NamedTuple{S, NTuple{3, T}}, metric, ω, elems, vmapM,
                  vmapP) where {S, T}
    rhsρ = rhs.ρ
    (ρ, U, V) = (Q.ρ, Q.U, Q.V)
    nface = 4
    (nx, ny, sJ) = (metric.nx, metric.ny, metric.sJ)
    for e ∈ elems
        for f ∈ 1:nface
            ρM = ρ[vmapM[:, f, e]]
            uM = U[vmapM[:, f, e]] ./ ρM
            vM = V[vmapM[:, f, e]] ./ ρM
            fM = ρM .* uM
            gM = ρM .* vM

            ρP = ρ[vmapP[:, f, e]]
            uP = U[vmapP[:, f, e]] ./ ρP
            vP = V[vmapP[:, f, e]] ./ ρP
            fP = ρP .* uP
            gP = ρP .* vP

            nxM = nx[:, f, e]
            nyM = ny[:, f, e]
            λ = max.(abs.(nxM .* uM + nyM .* vM), abs.(nxM .* uP + nyM .* vP))

            F = (nxM .* (fM + fP) + nyM .* (gM + gP) - λ .* (ρP - ρM)) / 2
            rhsρ[vmapM[:, f, e]] -= ω .* sJ[:, f, e] .* F
        end #f ∈ 1:nface
    end #e ∈ elems
end #function fluxrhs-2d

# FLux RHS for 3D
function fluxrhs!(rhs, Q::NamedTuple{S, NTuple{4, T}}, metric, ω, elems, vmapM,
                  vmapP) where {S, T}
    rhsρ = rhs.ρ
    (ρ, U, V, W) = (Q.ρ, Q.U, Q.V, Q.W)
    nface = 6
    (nx, ny, nz, sJ) = (metric.nx, metric.ny, metric.nz, metric.sJ)
    nx = reshape(nx, size(vmapM))
    ny = reshape(ny, size(vmapM))
    nz = reshape(nz, size(vmapM))
    sJ = reshape(sJ, size(vmapM))
    for e ∈ elems
        for f ∈ 1:nface
            ρM = ρ[vmapM[:, f, e]]
            uM = U[vmapM[:, f, e]] ./ ρM
            vM = V[vmapM[:, f, e]] ./ ρM
            wM = W[vmapM[:, f, e]] ./ ρM
            fM = ρM .* uM
            gM = ρM .* vM
            hM = ρM .* wM

            ρP = ρ[vmapP[:, f, e]]
            uP = U[vmapP[:, f, e]] ./ ρP
            vP = V[vmapP[:, f, e]] ./ ρP
            wP = W[vmapP[:, f, e]] ./ ρP
            fP = ρP .* uP
            gP = ρP .* vP
            hP = ρP .* wP

            nxM = nx[:, f, e]
            nyM = ny[:, f, e]
            nzM = nz[:, f, e]
            λ = max.(abs.(nxM .* uM + nyM .* vM + nzM .* wM),
                     abs.(nxM .* uP + nyM .* vP + nzM .* wP))

            F = (nxM .* (fM + fP) + nyM .* (gM + gP) + nzM .* (hM + hP) -
                 λ .* (ρP - ρM)) / 2
            rhsρ[vmapM[:, f, e]] -= kron(ω, ω) .* sJ[:, f, e] .* F
        end #f ∈ 1:nface
    end #e ∈ elems
end #function fluxrhs-3d

# ### Update the solution via RK Method for:
# Update 1D
function updatesolution!(rhs, Q::NamedTuple{S, NTuple{2, T}}, metric, ω, elems,
                         rka, rkb, dt) where {S, T}

    #Save original velocity
    u = Q.U ./ Q.ρ

    J = metric.J
    M =  ω
    for (rhsq, q) ∈ zip(rhs, Q)
        for e ∈ elems
            q[:, e] += rkb * dt * rhsq[:, e] ./ ( M .* J[:, e])
            rhsq[:, e] *= rka
        end
    end

    #Reset velocity
    Q.U .= Q.ρ .* u
end

# Update 2D
function updatesolution!(rhs, Q::NamedTuple{S, NTuple{3, T}}, metric, ω, elems,
                         rka, rkb, dt) where {S, T}
    #Save original velocity
    u = Q.U ./ Q.ρ
    v = Q.V ./ Q.ρ

    J = metric.J
    M = reshape(kron(ω, ω), length(ω), length(ω))
    for (rhsq, q) ∈ zip(rhs, Q)
        for e ∈ elems
            q[:, :, e] += rkb * dt * rhsq[:, :, e] ./ (M .* J[:, :, e])
            rhsq[:, :, e] *= rka
        end
    end

    #Reset velocity
    Q.U .= Q.ρ .* u
    Q.V .= Q.ρ .* v
end #function update-2d

# Update 3D
function updatesolution!(rhs, Q::NamedTuple{S, NTuple{4, T}}, metric, ω, elems,
                         rka, rkb, dt) where {S, T}
   #Save original velocity
    u = Q.U ./ Q.ρ
    v = Q.V ./ Q.ρ
    w = Q.W ./ Q.ρ

    J = metric.J
    M = reshape(kron(ω, ω, ω), length(ω), length(ω), length(ω))
    for (rhsq, q) ∈ zip(rhs, Q)
        for e ∈ elems
            q[:, :, :, e] += rkb * dt * rhsq[:, :, :, e] ./ (M .* J[:, :, :, e])
            rhsq[:, :, :, e] *= rka
        end
    end

    #Reset velocity
    Q.U .= Q.ρ .* u
    Q.V .= Q.ρ .* v
    Q.W .= Q.ρ .* w
end #function update-3d

# ### Compute L2 Error Norm for:
# 1D Error
function L2energy(Q::NamedTuple{S, NTuple{2, T}}, metric, ω, elems) where {S, T}
  J = metric.J
  Nq = length(ω)
  M = ω
  index = CartesianIndices(ntuple(j->1:Nq, Val(1)))

  energy = [zero(J[1])]
  for q ∈ Q
    for e ∈ elems
      for ind ∈ index
        energy[1] += M[ind] * J[ind, e] * q[ind, e]^2
      end
    end
  end
  energy[1]
end #function L2energy-1d

# 2D Error
function L2energy(Q::NamedTuple{S, NTuple{3, T}}, metric, ω, elems) where {S, T}
  J = metric.J
  Nq = length(ω)
  M = reshape(kron(ω, ω), Nq, Nq)
  index = CartesianIndices(ntuple(j->1:Nq, Val(2)))

  energy = [zero(J[1])]
  for q ∈ Q
    for e ∈ elems
      for ind ∈ index
        energy[1] += M[ind] * J[ind, e] * q[ind, e]^2
      end
    end
  end
  energy[1]
end #function L2energy-2d

# 3D Error
function L2energy(Q::NamedTuple{S, NTuple{4, T}}, metric, ω, elems) where {S, T}
  J = metric.J
  Nq = length(ω)
  M = reshape(kron(ω, ω, ω), Nq, Nq, Nq)
  index = CartesianIndices(ntuple(j->1:Nq, Val(3)))

  energy = [zero(J[1])]
  for q ∈ Q
    for e ∈ elems
      for ind ∈ index
        energy[1] += M[ind] * J[ind, e] * q[ind, e]^2
      end
    end
  end
  energy[1]
end #function L2energy-3d

#-------------------------------------------------------------------------------#
#--------End Volume, Flux, Update, Error Functions for Multiple Dispatch--------#
#-------------------------------------------------------------------------------#

# ### Compute how many MPI neighbors we have
# "mesh.nabrtorank" stands for "Neighbors to rank"
numnabr = length(mesh.nabrtorank)

# ### Create send/recv request arrays
# "sendreq" is the array that we use to send the communication request. It needs to be of the same length as the number of neighboring ranks. Similarly, "recvreq" is the array that we use to receive the neighboring rank information.
sendreq = fill(MPI.REQUEST_NULL, numnabr)
recvreq = fill(MPI.REQUEST_NULL, numnabr)

# ### Create send/recv buffer
# The dimensions of these arrays are (1) degrees of freedom within an element, (2) number of solution vectors, and (3) the number of "send elements" and "ghost elements", respectively.
sendQ = Array{DFloat, 3}(undef, (N+1)^dim, length(Q), length(mesh.sendelems))
recvQ = Array{DFloat, 3}(undef, (N+1)^dim, length(Q), length(mesh.ghostelems))

# Build CartesianIndex map for moving between Cartesian and linear storage of
# dofs
index = CartesianIndices(ntuple(j->1:N+1, dim))
nrealelem = length(mesh.realelems)

# ### Dump the initial condition
# Dump out the initial conditin to VTK prior to entering the time-step loop.
include("vtk.jl")
writemesh(@sprintf("SWE%dD_rank_%04d_step_%05d", dim, mpirank, 0),
          coord...; fields=(("ρ", Q.ρ),), realelems=mesh.realelems)

# ### Begin Time-step loop
# Go through nsteps time-steps and for each time-step, loop through the s-stages of the explicit RK method.
for step = 1:nsteps
    mpirank == 0 && @show step
    for s = 1:length(RKA)
        # #### Post MPI receives
        # We assume that an MPI_Isend has been posted (non-blocking send) and are waiting to receive any message that has
        # been posted for receiving.  We are looping through the : (1) number of neighbors, (2) neighbor ranks,
        # and (3) neighbor elements.
        for (nnabr, nabrrank, nabrelem) ∈ zip(1:numnabr, mesh.nabrtorank,
                                              mesh.nabrtorecv)
            recvreq[nnabr] = MPI.Irecv!((@view recvQ[:, :, nabrelem]), nabrrank, 777,
                                        mpicomm)
        end

        # #### Wait on (prior) MPI sends
        # WE assume that non-blocking sends have been sent and wait for this to happen. FXG: Why do we need to wait?
        MPI.Waitall!(sendreq)

        # #### Pack data to send buffer
        # For all faces "nf" and all elements "ne" we pack the send data.
        for (ne, e) ∈ enumerate(mesh.sendelems)
            for (nf, f) ∈ enumerate(Q)
                sendQ[:, nf, ne] = f[index[:], e]
            end
        end

        # #### Post MPI sends
        # For all: (1) number of neighbors, (2) neighbor ranks, and (3) neighbor elements we perform a non-blocking send.
        for (nnabr, nabrrank, nabrelem) ∈ zip(1:numnabr, mesh.nabrtorank,
                                              mesh.nabrtosend)
            sendreq[nnabr] = MPI.Isend((@view sendQ[:, :, nabrelem]), nabrrank, 777,
                                       mpicomm)
        end

        # #### Compute RHS Volume Integral
        # Note that it is not necessary to have received all the MPI messages. Here we are interleaving computation
        # with communication in order to curtail latency.  Here we perform the RHS volume integrals.
        volumerhs!(rhs, Q, metric, D, ω, mesh.realelems)

        # #### Wait on MPI receives
        # We need to wait to receive the messages before we move on to t=e flux integrals.
        MPI.Waitall!(recvreq)

        # #### Unpack data from receive buffer
        # The inverse of the Pack datat to send buffer. We now unpack the receive buffer in order to use it in the RHS
        # flux integral.
        for elems ∈ mesh.nabrtorecv
            for (nf, f) ∈ enumerate(Q)
                f[index[:], nrealelem .+ elems] = recvQ[:, nf, elems]
            end
        end

        # #### Compute RHS Flux Integral
        # We compute the flux integral on all "realelems" which are the elements owned by the current mpirank.
        fluxrhs!(rhs, Q, metric, ω, mesh.realelems, vmapM, vmapP)

        # #### Update solution and scale RHS
        # We need to update/evolve the solution in time and multiply by the inverse mass matrix.
        updatesolution!(rhs, Q, metric, ω, mesh.realelems, RKA[s%length(RKA)+1],
                        RKB[s], dt)
    end

    # #### Write VTK Output
    # After each time-step, we dump out VTK data for Paraview/VisIt.
    writemesh(@sprintf("SWE%dD_rank_%04d_step_%05d", dim, mpirank, step),
              coord...; fields=(("ρ", Q.ρ),), realelems=mesh.realelems)
end

# ### Compute L2 Error Norms
# Since we stored the initial condition, we can now compute the L2 error norms for both the solution and energy.

#extract velocity fields
if dim == 1
    Q.U .= Q.U ./ Q.ρ
    Δ.U .= Δ.U ./ Δ.ρ
    Q.ρ .= Q.ρ .- 2
    Δ.ρ .= Δ.ρ .- 2
elseif dim == 2
    Q.U .= Q.U ./ Q.ρ
    Δ.U .= Δ.U ./ Δ.ρ
    Q.V .= Q.V ./ Q.ρ
    Δ.V .= Δ.V ./ Δ.ρ
    Q.ρ .= Q.ρ .- 2
    Δ.ρ .= Δ.ρ .- 2
elseif dim == 3
    Q.U .= Q.U ./ Q.ρ
    Δ.U .= Δ.U ./ Δ.ρ
    Q.V .= Q.V ./ Q.ρ
    Δ.V .= Δ.V ./ Δ.ρ
    Q.W .= Q.W ./ Q.ρ
    Δ.W .= Δ.W ./ Δ.ρ
    Q.ρ .= Q.ρ .- 2
    Δ.ρ .= Δ.ρ .- 2
end

#Compute Norms
for (δ, q) ∈ zip(Δ, Q)
    δ .-= q
end
eng = L2energy(Q, metric, ω, mesh.realelems)
eng = MPI.Allreduce(eng, MPI.SUM, mpicomm)
mpirank == 0 && @show sqrt(eng)

err = L2energy(Δ, metric, ω, mesh.realelems)
err = MPI.Allreduce(err, MPI.SUM, mpicomm)
mpirank == 0 && @show sqrt(err)

nothing

#-
#md # ## [Plain Program](@id shallow_water-plain-program)
#md #
#md # Below follows a version of the program without any comments.
#md # The file is also available here: [shallow_water.jl](shallow_water.jl)
#md #
#md # ```julia
#md # @__CODE__
#md # ```

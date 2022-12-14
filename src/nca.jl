"""
    svectorscopy(x, n::Val{N})

Convert Matrix to a vector of static arrays

# Arguments
- `x` a matrix.
- `n` should be `Val(N)` where `N = size(x,1)`.
"""
function svectorscopy(x::Matrix{T}, ::Val{N}) where {T,N}
    size(x,1) == N || error("sizes mismatch")
    isbitstype(T) || error("use for bitstypes only")
    copy(reinterpret(SVector{N,T}, vec(x)))
end

"""
    NCA(A, x, y; objective)

Compute the NCA objective function for matrix A with data x and y, using defined objective scaling.

# Arguments:

- `A` should be a `SMatrix` with dimensions `P` and `D`.
- `x` should be an `AbstractVector` of `SVector`s, each of which is a point in the space.
- `y` should be an `AbstractVector` containing the classes of the `x` points.
- `objective` is a named argument which whould be of type `NCAMethod`. Choose from:
    - `NCAStandard()` for standard (which is the default).
    - `NCALog()` for log.

If optimising NCA, use the following:
- `A` should be a Matrix.
- `x` should be an `AbstractVector` of `SVector`s, each of which is a point in the space.
- `y` should be an `AbstractVector` containing the classes of the `x` points.
- `objective` is a named argument which should be of type `NCAMethod`. Choose from:
    - `NCAStandard()` for standard (which is the default).
    - `NCALog()` for log.
- `dims` is an additional named argument which should be `Val(P)` where `P = size(A, 1)`, the solution dimension.

# Examples:
```julia
julia> A = SMatrix{2,2,Float64}([1.0 2; 3 4]) # generate A

julia> x_matrix = rand(MvNormal(ones(2),[1 0; 0 1]),100) # generate matrix of x values

julia> x = svectorscopy(x_matrix, Val(2)) # convert to vector of SVectors

julia> y = rand(Bernoulli(0.5),100) # generate y

julia> NCA(A,x,y) # standard objective

julia> NCA(A,x,y,objective = NCALog()) # log objective

julia> A_initial = [1.0 0; 0 1] # generate initial A for optimisation

julia> optimize(A -> NCA(A, x, y, dims = Val(2)), A_initial, LBFGS())
```

"""
function NCA(A, x::AbstractVector{SVector{D,T}}, y::AbstractVector; objective=NCAStandard(), dims::Val{P}) where {P,D,T,L}
    A = SMatrix{P,D,T}(A)
    NCA(A, x, y; objective=objective)
end
function NCA(A::SMatrix{P,D,T,L}, x::AbstractVector{SVector{D,T}}, y::AbstractVector; objective::NCAMethod=NCAStandard()) where {P,D,T,L}
    length(x)==length(y) || throw(ArgumentError("x and y should be of the same length."))
    M = transpose(A) * A
    d = SqMahalanobis(M, skipchecks = true)
    value = 0.0
    distances = Vector{T}(undef, length(x))
    @views for i ??? eachindex(x)
        distances .= d.(Ref(x[i]), x)
        distances .-= minimum(distances[j] + Inf * (i == j) for j ??? eachindex(x))
        p??? = zero(eltype(distances))
        total??? = zero(eltype(distances))
        for j ??? eachindex(distances,y)
            p??? += exp(-distances[j]) * (y[j] == y[i]) * (j!=i)
            total??? += exp(-distances[j]) * (j!=i) 
        end
        if objective isa NCAStandard
            value += p???/total???
        elseif objective isa NCALog
            value += log(p???)-log(total???)
        end
    end
    return -value
end

"""
    NCAfg!(F, G, A, x, y; objective, dims)

NCAfg! calculates the NCA objective and gradient function together, for more efficient optimisation.

# Arguments:

- `A` should be a Matrix.
- `x` should be an `AbstractVector` of `SVector`s, each of which is a point in the space.
- `y` should be an `AbstractVector` containing the classes of the `x` points.
- `objective` is a named argument which whould be of type `NCAMethod`. Choose from:
    - `NCAStandard()` for standard (which is the default).
    - `NCALog()` for log.
- `dims` should be `Val(P)` where `P = size(A, 1)`, the solution dimension.

# Examples:
```julia
julia> A_initial = SMatrix{2,2,Float64}([1.0 2; 3 4]) # generate initial A

julia> x_matrix = rand(MvNormal(ones(2),[1 0; 0 1]),100) # generate matrix of x values

julia> x = svectorscopy(x_matrix, Val(2)) # convert to vector of SVectors

julia> y = rand(Bernoulli(0.5),100) # generate y

julia> optimize(Optim.only_fg!((F,G,A) -> NCAfg!(F,G,A,x,y,dims=Val(2))), A_initial, LBFGS()) # standard objective

julia> optimize(Optim.only_fg!((F,G,A) -> NCAfg!(F,G,A,x,y,objective=NCALog(),dims=Val(2))), A_initial, LBFGS()) # log objective
```

"""

function NCAfg!(F, G, A, x::AbstractVector{SVector{D,T}}, y::AbstractVector; objective::NCAMethod=NCAStandard(), dims::Val{P}) where {P,D,T,L}
    A = SMatrix{P,D,T}(A)
    length(x)==length(y) || throw(ArgumentError("x and y should be of the same length."))
    M = transpose(A) * A
    d = SqMahalanobis(M, skipchecks = true)
    if G != nothing
        Gvalue = zeros(D,D)
    end
    if F != nothing
        Fvalue = 0.0
    end
    distances = Vector{T}(undef, length(x))
    @views for i ??? eachindex(x)
        distances .= d.(Ref(x[i]), x)
        distances .-= minimum(distances[j] + Inf * (i == j) for j ??? eachindex(x)) 
        p??? = zero(eltype(distances))
        total??? = zero(eltype(distances))
        for j ??? eachindex(distances,y)
            p??? += exp(-distances[j]) * (y[j] == y[i]) * (j!=i)
            total??? += exp(-distances[j]) * (j!=i)
        end
        if G != nothing
            sum1??? = SMatrix{D,D}(zeros(D,D))
            sum2??? = SMatrix{D,D}(zeros(D,D))
            for j ??? eachindex(distances,y)
                sum1??? += exp(-distances[j]) * (x[i]-x[j])*transpose(x[i]-x[j])
                sum2??? += exp(-distances[j]) * (y[j] == y[i]) * (x[i]-x[j])*transpose(x[i]-x[j])
            end
            if objective isa NCAStandard
                Gvalue += (p??? * sum1???/(total???^2)) - sum2???/total???
            elseif objective isa NCALog
                Gvalue += sum1???/total??? - sum2???/p???
            end
        end
        if F != nothing
            if objective isa NCAStandard
                Fvalue += p???/total???
            elseif objective isa NCALog
                Fvalue += log(p???)-log(total???)
            end
        end
    end
    if G != nothing
        G[:] = -2A * Gvalue
    end
    if F != nothing
        return -Fvalue
    end
end


"""
    NCArepeats(A, x, y; objective)

Compute the NCA objective function for matrix A with data x and y, using defined objective scaling.
Use `NCArepeats` instead of `NCA` for faster computation when x contains repeated elements.

# Arguments:

- `A` should be a `SMatrix` with dimensions `P` and `D`. When optimising NCArepeats, `A` should be a Matrix, so we include another NCArepeats function to accommodate this.
- `x` should be an `AbstractVector` of `SVector`s, each of which is a point in the space.
- `y` should be an `AbstractVector` containing the classes of the `x` points.
- `objective` is a named argument which whould be of type `NCAMethod`. Choose from:
    - `NCAStandard()` for standard (which is the default).
    - `NCALog()` for log.

If optimising NCArepeats, use the following:
- `A` should be a Matrix.
- `x` should be an `AbstractVector` of `SVector`s, each of which is a point in the space.
- `y` should be an `AbstractVector` containing the classes of the `x` points.
- `objective` is a named argument which should be of type `NCAMethod`. Choose from:
    - `NCAStandard()` for standard (which is the default).
    - `NCALog()` for log.
- `dims` is an additional named argument which should be `Val(P)` where `P = size(A, 1)`, the solution dimension.

# Examples:
```julia
julia> A = SMatrix{2,2,Float64}([1.0 2; 3 4]) # generate A

julia> x_matrix = rand(MvNormal(ones(2),[1 0; 0 1]),100) # generate matrix of x values

julia> x = svectorscopy(x_matrix, Val(2)) # convert to vector of SVectors

julia> y = rand(Bernoulli(0.5),100) # generate y

julia> NCArepeats(A,x,y) # standard objective

julia> NCArepeats(A,x,y,objective = NCALog()) # log objective

julia> A_initial = [1.0 0; 0 1] # generate initial A for optimisation

julia> optimize(A -> NCArepeats(A, x, y, dims = Val(2)), A_initial, LBFGS())
```
"""
function NCArepeats(A, x::AbstractVector{SVector{D,T}}, y::AbstractVector; objective=NCAStandard(), dims::Val{P}) where {P,D,T,L}
    A = SMatrix{P,D,T}(A)
    NCArepeats(A, x, y; objective=objective)
end
function NCArepeats(A::SMatrix{P,D,T,L}, x::AbstractVector{SVector{D,T}}, y::AbstractVector; objective::NCAMethod=NCAStandard()) where {P,D,T,L}
    length(x)==length(y) || throw(ArgumentError("x and y should be of the same length."))
    joint = [(x???,y???) for (x???,y???) ??? zip(x,y)]
    cells = countmap(joint)
    M = transpose(A) * A
    d = SqMahalanobis(M, skipchecks = true)
    value = 0.0
    distances = Vector{T}(undef, length(cells))
    for k??? in keys(cells)
        for (j,k???) ??? enumerate(keys(cells))
            distances[j] = d(k???[1], k???[1])
        end 
        p??? = zero(eltype(distances))
        total??? = zero(eltype(distances))
        for (j,k???) ??? enumerate(keys(cells))
            if k???[1] == k???[1] && k???[2] == k???[2]
                tmp = exp(-distances[j]) * cells[k???]-1
            else
                tmp = exp(-distances[j]) * cells[k???]
            end
            p??? += tmp * (k???[2] == k???[2]) 
            total??? += tmp
        end
        if objective isa NCAStandard
            value += p???/total??? * cells[k???]
        elseif objective isa NCALog
            value += (log(p???)-log(total???)) * cells[k???]
        end
    end
    return -value
end

"""
    NCArepeatsfg!(F, G, A, x, y; objective, dims)

NCArepeatsfg! calculates the NCA objective and gradient function together, for more efficient optimisation.
Use `NCArepeatsfg!` instead of `NCAfg!` for faster optimisation when x contains repeated elements.

# Arguments:

- `A` should be a Matrix.
- `x` should be an `AbstractVector` of `SVector`s, each of which is a point in the space.
- `y` should be an `AbstractVector` containing the classes of the `x` points.
- `objective` is a named argument which whould be of type `NCAMethod`. Choose from:
    - `NCAStandard()` for standard (which is the default).
    - `NCALog()` for log.
- `dims` should be `Val(P)` where `P = size(A, 1)`, the solution dimension.

# Examples:
```julia
julia> initial_A = SMatrix{2,2,Float64}([1.0 2; 3 4]) # generate initial A

julia> x_matrix = rand(MvNormal(ones(2),[1 0; 0 1]),100) # generate matrix of x values

julia> x = svectorscopy(x_matrix, Val(2)) # convert to vector of SVectors

julia> y = rand(Bernoulli(0.5),100) # generate y

julia> optimize(Optim.only_fg!((F,G,A) -> NCArepeatsfg!(F,G,A,x,y,dims=Val(2))), initial_A, LBFGS()) # standard objective

julia> optimize(Optim.only_fg!((F,G,A) -> NCArepeatsfg!(F,G,A,x,y,objective=NCALog(),dims=Val(2))), initial_A, LBFGS()) # log objective
```

"""

function NCArepeatsfg!(F, G, A, x::AbstractVector{SVector{D,T}}, y::AbstractVector; objective::NCAMethod=NCAStandard(), dims::Val{P}) where {P,D,T,L}
    length(x)==length(y) || throw(ArgumentError("x and y should be of the same length."))
    joint = [(x???,y???) for (x???,y???) ??? zip(x,y)]
    cells = countmap(joint)
    d = SqEuclidean()
    if G != nothing
        Gvalue = zeros(D,D)
    end
    if F != nothing
        Fvalue = 0.0
    end
    distances = Vector{T}(undef, length(cells))
    for k??? in keys(cells)
        for (j,k???) ??? enumerate(keys(cells))
            distances[j] = d(A*k???[1], A*k???[1])
        end
        p??? = zero(eltype(distances))
        total??? = zero(eltype(distances))
        for (j,k???) ??? enumerate(keys(cells))
            if k???[1] == k???[1] && k???[2] == k???[2]
                tmp = exp(-distances[j]) * cells[k???]-1
            else
                tmp = exp(-distances[j]) * cells[k???]
            end
            p??? += tmp * (k???[2] == k???[2]) 
            total??? += tmp
        end
        if G != nothing
            sum1??? = SMatrix{D,D}(zeros(D,D))
            sum2??? = SMatrix{D,D}(zeros(D,D))
            for (j,k???) ??? enumerate(keys(cells))
                tmpmat = exp(-distances[j])*cells[k???] * (k???[1]-k???[1])*transpose(k???[1]-k???[1])
                sum1??? += tmpmat
                sum2??? += tmpmat * (k???[2] == k???[2])
            end
            if objective isa NCAStandard
                Gvalue += cells[k???] * ((p???*sum1???/(total???^2)) - sum2???/total???)
            elseif objective isa NCALog
                Gvalue += cells[k???] * (sum1???/total??? - sum2???/p???)
            end
        end
        if F != nothing
            if objective isa NCAStandard
                Fvalue += cells[k???] * p???/total???
            elseif objective isa NCALog
                Fvalue += cells[k???] * (log(p???)-log(total???))
            end
        end
    end
    if G != nothing
        G[:] = -2A * Gvalue
    end
    if F != nothing
        return -Fvalue
    end   
end
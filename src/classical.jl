struct Solver{S,T,P,PS}
    strength::S
    CF::T
    presmoother::P
    postsmoother::PS
    max_levels::Int64
    max_coarse::Int64
end

struct Level{T}
    A::T
end

function ruge_stuben(A::SparseMatrixCSC;
                strength = Classical(),
                CF = RS(),
                presmoother = GaussSiedel(),
                postsmoother = GaussSiedel(),
                max_levels = 10,
                max_coarse = 500)

        s = Solver(strength, CF, presmoother,
                    postsmoother, max_levels, max_levels)

        levels = [Level(A)]

        while length(levels) < max_levels && size(levels[end].A, 1)
            extend_heirarchy!(levels, strength, CF, A)
        end
end

function extend_heirarchy!(levels::Vector{Level}, strength, CF, A)
    S = strength_of_connection(strength, A)
    splitting = split_nodes(CF, S)
    P, R = direct_interpolation(A, S, splitting)
end

function direct_interpolation{T,V}(A::T, S::T, splitting::Vector{V})
    
    fill!(S.nzval, 1.)
    S = A .* S
    Pp = rs_direct_interpolation_pass1(S, A, splitting)
    Pp .= Pp .+ 1

    Px, Pj = rs_direct_interpolation_pass2(A, S, splitting, Pp)

    Px .= abs.(Px)
    Pj .= Pj .+ 1

    R = SparseMatrixCSC(maximum(Pj), size(A, 1), Pp, Pj, Px)
    P = R'

    P, R
end


function rs_direct_interpolation_pass1(S, A, splitting)

     Bp = zeros(Int, size(A.colptr))
     Sp = S.colptr
     Sj = S.rowval
     n_nodes = size(A, 1)
     nnz = 0
     for i = 1:n_nodes
         if splitting[i] == C_NODE
             nnz += 1
         else
            for jj = Sp[i]:Sp[i+1]-1
                if splitting[Sj[jj]] == C_NODE && Sj[jj] != i
                    nnz += 1
                end
            end
        end
         Bp[i+1] = nnz
     end
     Bp
 end


 function rs_direct_interpolation_pass2{Tv, Ti}(A::SparseMatrixCSC{Tv,Ti},
                                                S::SparseMatrixCSC{Tv,Ti},
                                                splitting::Vector{Ti},
                                                Bp::Vector{Ti})


    Ap = A.colptr
    Aj = A.rowval
    Ax = A.nzval
    Sp = S.colptr
    Sj = S.rowval
    Sx = S.nzval
    Bj = zeros(Ti, Bp[end])
    Bx = zeros(Float64, Bp[end])
    n_nodes = size(A, 1)
    #Bp += 1

    for i = 1:n_nodes
        if splitting[i] == C_NODE
            Bj[Bp[i]] = i
            Bx[Bp[i]] = 1
        else
            sum_strong_pos = 0
            sum_strong_neg = 0
            for jj = Sp[i]: Sp[i+1]-1
                if splitting[Sj[jj]] == C_NODE && Sj[jj] != i
                    if Sx[jj] < 0
                        sum_strong_neg += Sx[jj]
                    else
                        sum_strong_pos += Sx[jj]
                    end
                end
            end

            sum_all_pos = 0
            sum_all_neg = 0
            diag = 0;
            for jj = Ap[i]:Ap[i+1]
                if Aj[jj] == i
                    diag += Ax[jj]
                else
                    if Ax[jj] < 0
                        sum_all_neg += Ax[jj];
                    else
                        sum_all_pos += Ax[jj];
                    end
                end
            end

            alpha = sum_all_neg / sum_strong_neg
            beta  = sum_all_pos / sum_strong_pos

            if sum_strong_pos == 0
                diag += sum_all_pos
                beta = 0
            end

            neg_coeff = -alpha/diag;
            pos_coeff = -beta/diag;

            nnz = Bp[i]
            for jj = Sp[i]:Sp[i+1]
                if splitting[Sj[jj]] == C_NODE && Sj[jj] != i
                    Bj[nnz] = Sj[jj]
                    if Sx[jj] < 0
                        Bx[nnz] = neg_coeff * Sx[jj]
                    else
                        Bx[nnz] = pos_coeff * Sx[jj]
                        nnz += 1
                    end
                end
            end
        end
    end

   m = zeros(Ti, n_nodes)
   sum = 0
   for i = 1:n_nodes
       m[i] = sum
       sum += splitting[i]
   end
   for i = 1:Bp[n_nodes]
       Bj[i] = m[Bj[i]]
   end

   Bx, Bj, Bp
end
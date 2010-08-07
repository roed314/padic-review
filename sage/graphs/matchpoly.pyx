"""
Matching Polynomial Routine

AUTHORS:
    -- Robert Miller - original implementation

REFERENCE:
    Chris Godsil, Algebraic Combinatorics.

"""

#*****************************************************************************
#                       Copyright (C) 2010 Robert Miller
#
# Distributed  under  the  terms  of  the  GNU  General  Public  License (GPL)
#                         http://www.gnu.org/licenses/
#*****************************************************************************

from sage.rings.integer_ring import ZZ
from sage.rings.integer cimport Integer
from sage.misc.misc import prod
include '../ext/interrupt.pxi'
include '../ext/cdefs.pxi'
include '../ext/stdsage.pxi'
include '../libs/flint/fmpz.pxi'
include '../libs/flint/fmpz_poly.pxi'

R = ZZ['x']
x = R.gen()

def matching_polynomial(G, complement=True, name=None):
    """
    Computes the matching polynomial of the graph G.
    
    The algorithm used is a recursive one, based on the following observation:
    
    - If e is an edge of G, G' is the result of deleting the edge e, and G''
        is the result of deleting each vertex in e, then the matching
        polynomial of G is equal to that of G' minus that of G''.

    EXAMPLES::
    
        sage: from sage.graphs.matchpoly import matching_polynomial
        sage: for i in [1..12]:
        ...    for t in graphs.trees(i):
        ...        c = t.complement()
        ...        assert matching_polynomial(t) == t.characteristic_polynomial()
        ...        assert matching_polynomial(c, complement=False) == matching_polynomial(c)

    ::

        sage: matching_polynomial(graphs.CompleteGraph(0))
        1
        sage: matching_polynomial(graphs.CompleteGraph(1))
        x
        sage: matching_polynomial(graphs.CompleteGraph(2))
        x^2 - 1
        sage: matching_polynomial(graphs.CompleteGraph(3))
        x^3 - 3*x
        sage: matching_polynomial(graphs.CompleteGraph(4))
        x^4 - 6*x^2 + 3
        sage: matching_polynomial(graphs.CompleteGraph(5))
        x^5 - 10*x^3 + 15*x
        sage: matching_polynomial(graphs.CompleteGraph(6))
        x^6 - 15*x^4 + 45*x^2 - 15
        sage: matching_polynomial(graphs.CompleteGraph(7))
        x^7 - 21*x^5 + 105*x^3 - 105*x
        sage: matching_polynomial(graphs.CompleteGraph(8))
        x^8 - 28*x^6 + 210*x^4 - 420*x^2 + 105
        sage: matching_polynomial(graphs.CompleteGraph(9))
        x^9 - 36*x^7 + 378*x^5 - 1260*x^3 + 945*x
        sage: matching_polynomial(graphs.CompleteGraph(10))
        x^10 - 45*x^8 + 630*x^6 - 3150*x^4 + 4725*x^2 - 945
        sage: matching_polynomial(graphs.CompleteGraph(11))
        x^11 - 55*x^9 + 990*x^7 - 6930*x^5 + 17325*x^3 - 10395*x
        sage: matching_polynomial(graphs.CompleteGraph(12))
        x^12 - 66*x^10 + 1485*x^8 - 13860*x^6 + 51975*x^4 - 62370*x^2 + 10395
        sage: matching_polynomial(graphs.CompleteGraph(13))
        x^13 - 78*x^11 + 2145*x^9 - 25740*x^7 + 135135*x^5 - 270270*x^3 + 135135*x
        sage: 13*11*9*7*5*3
        135135
        sage: binomial(13,5)*7*5*3
        135135
        sage: 11*9*7*5*3
        10395
        sage: binomial(9,3)*5*3
        1260
        sage: 9*7*5*3
        945

    ::

        sage: G = Graph({0:[1,2], 1:[2]})
        sage: matching_polynomial(G)
        x^3 - 3*x
        sage: G = Graph({0:[1,2]})
        sage: matching_polynomial(G)
        x^3 - 2*x
        sage: G = Graph({0:[1], 2:[]})
        sage: matching_polynomial(G)
        x^3 - x
        sage: G = Graph({0:[], 1:[], 2:[]})
        sage: matching_polynomial(G)
        x^3

    ::

        sage: matching_polynomial(graphs.CompleteGraph(0), complement=False)
        1
        sage: matching_polynomial(graphs.CompleteGraph(1), complement=False)
        x
        sage: matching_polynomial(graphs.CompleteGraph(2), complement=False)
        x^2 - 1
        sage: matching_polynomial(graphs.CompleteGraph(3), complement=False)
        x^3 - 3*x
        sage: matching_polynomial(graphs.CompleteGraph(4), complement=False)
        x^4 - 6*x^2 + 3
        sage: matching_polynomial(graphs.CompleteGraph(5), complement=False)
        x^5 - 10*x^3 + 15*x
        sage: matching_polynomial(graphs.CompleteGraph(6), complement=False)
        x^6 - 15*x^4 + 45*x^2 - 15
        sage: matching_polynomial(graphs.CompleteGraph(7), complement=False)
        x^7 - 21*x^5 + 105*x^3 - 105*x
        sage: matching_polynomial(graphs.CompleteGraph(8), complement=False)
        x^8 - 28*x^6 + 210*x^4 - 420*x^2 + 105
        sage: matching_polynomial(graphs.CompleteGraph(9), complement=False)
        x^9 - 36*x^7 + 378*x^5 - 1260*x^3 + 945*x
        sage: matching_polynomial(graphs.CompleteGraph(10), complement=False)
        x^10 - 45*x^8 + 630*x^6 - 3150*x^4 + 4725*x^2 - 945
        sage: matching_polynomial(graphs.CompleteGraph(11), complement=False)
        x^11 - 55*x^9 + 990*x^7 - 6930*x^5 + 17325*x^3 - 10395*x
        sage: matching_polynomial(graphs.CompleteGraph(12), complement=False)
        x^12 - 66*x^10 + 1485*x^8 - 13860*x^6 + 51975*x^4 - 62370*x^2 + 10395
        sage: matching_polynomial(graphs.CompleteGraph(13), complement=False)
        x^13 - 78*x^11 + 2145*x^9 - 25740*x^7 + 135135*x^5 - 270270*x^3 + 135135*x

    """
    
    cdef int nverts, nedges, i, j, v, cur
    cdef int *edges1, *edges2, *edges_mem, **edges
    cdef fmpz_poly_t pol
    
    if G.has_multiple_edges():
        raise NotImplementedError
    
    G = G.relabel(inplace=False)
    G.allow_loops(False)
    nverts = G.num_verts()
    if complement and G.density() > 0.5: # this cutoff could probably be tuned
        f_comp = matching_polynomial(G.complement()).list()
        f = R(0)
        for i from 0 <= i <= nverts/2: # implicit floor
            j = nverts - 2*i
            f += complete_poly(j)*f_comp[j]*(-1)**i
        return f

    nedges = G.num_edges()
    
    L = []
    for v, d in G.degree_iterator(labels=True):
        L.append((d,v))
    L.sort()
    d = {}
    for i from 0 <= i < nverts:
        d[L[i][1]] = i
    G = G.relabel(d, inplace=False)
    
    fmpz_poly_init(pol) # sets to zero
    edges_mem = <int *> sage_malloc(2 * nedges * nedges * sizeof(int))
    edges = <int **> sage_malloc(2 * nedges * sizeof(int *))
    if edges_mem is NULL or \
       edges is NULL:
        if edges_mem is not NULL:
            sage_free(edges_mem)
        if edges is not NULL:
            sage_free(edges)
        raise MemoryError("Error allocating memory for matchpoly.")
    
    for i from 0 <= i < nedges:
        edges[2*i] = edges_mem + nedges * (2*i)
        edges[2*i+1] = edges_mem + nedges * (2*i+1)

    edges1 = edges[0]
    edges2 = edges[1]

    cur = 0
    for i from 0 <= i < nverts:
        for j from i < j < nverts:
            if G.has_edge(i,j):
                edges1[cur] = i
                edges2[cur] = j
                cur += 1
    
    _sig_on
    delete_and_add(edges, nverts, nedges, nverts, 0, pol)
    _sig_off
    
    coeffs_ZZ = []
    cdef Integer c_ZZ
    for i from 0 <= i <= nverts:
        c_ZZ = Integer(0)
        fmpz_poly_get_coeff_mpz(c_ZZ.value, pol, i)
        coeffs_ZZ.append(c_ZZ*(-1)**((nverts-i)/2))
    f = R(coeffs_ZZ)
    sage_free(edges_mem)
    sage_free(edges)
    fmpz_poly_clear(pol)
    if name is not None:
        return f.change_variable_name(name)
    return f


# The following is a cache of complete graph matching polynomials.
# The code which computes new complete graph polynmials could probably
# be made more efficient by using FLINT polynomials and being written
# in Cython, using an array of fmpz_poly_t pointers or something...
# Right now just about the whole complement optimization is written
# in Python, and could be easily sped up.


cdef list complete_matching_polys = [R(1), x]

def complete_poly(n):
    """
    Compute the matching polynomial of the complete graph on `n` vertices.
    
    EXAMPLES::
    
        sage: from sage.graphs.matchpoly import complete_poly
        sage: f = complete_poly(10)
        sage: f
        x^10 - 45*x^8 + 630*x^6 - 3150*x^4 + 4725*x^2 - 945
        sage: f = complete_poly(20)
        sage: f[8]
        1309458150
        sage: f = complete_poly(1000)
        sage: len(str(f))
        406824

    """
    # global complete_matching_polys # if we do eventually make it a C array...
    cdef int lcmp = len(complete_matching_polys)
    if n < lcmp:
        return complete_matching_polys[n]
    lcmp -= 2
    a = complete_matching_polys[lcmp]
    b = complete_matching_polys[lcmp+1]
    while lcmp+2 <= n:
        a, b, lcmp = b, x*b - (lcmp+1)*a, lcmp+1
        complete_matching_polys.append(b)
    return b

cdef void delete_and_add(int **edges, int nverts, int nedges, int totverts, int depth, fmpz_poly_t pol):
    """
    Add matching polynomial to pol via recursion.
    """
    cdef int i, j, k, edge1, edge2, new_edge1, new_edge2, new_nedges
    cdef int *edges1, *edges2, *new_edges1, *new_edges2
    cdef fmpz_t coeff

    if nverts == 3:
        coeff = fmpz_poly_get_coeff_ptr(pol, 3)
        if coeff is NULL:
            fmpz_poly_set_coeff_ui(pol, 3, 1)
        else:
            fmpz_add_ui_inplace(coeff, 1)
        coeff = fmpz_poly_get_coeff_ptr(pol, 1)
        if coeff is NULL:
            fmpz_poly_set_coeff_ui(pol, 1, nedges)
        else:
            fmpz_add_ui_inplace(coeff, nedges)
        return

    if nedges == 0:
        coeff = fmpz_poly_get_coeff_ptr(pol, nverts)
        if coeff is NULL:
            fmpz_poly_set_coeff_ui(pol, nverts, 1)
        else:
            fmpz_add_ui_inplace(coeff, 1)
        return
    
    edges1 = edges[2*depth]
    edges2 = edges[2*depth + 1]
    new_edges1 = edges[2*depth + 2]
    new_edges2 = edges[2*depth + 3]

    nedges -= 1
    edge1 = edges1[nedges]
    edge2 = edges2[nedges]
    new_nedges = 0
    for i from 0 <= i < nedges:
        if edge1 == edges1[i]:
            break # since the rest of the edges are incident to edge1
        if edge1 != edges2[i] and edge2 != edges2[i]:
            # since edge2 > edge1 > edges1[i], only need to check edges2[i]
            new_edges1[new_nedges] = edges1[i]
            new_edges2[new_nedges] = edges2[i]
            new_nedges += 1

    delete_and_add(edges, nverts-2, new_nedges, totverts, depth+1, pol)
    delete_and_add(edges, nverts, nedges, totverts, depth, pol)

    

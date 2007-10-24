include "../../libs/polybori/decl.pxi"

from sage.structure.parent_base cimport ParentWithBase 
from sage.rings.polynomial.multi_polynomial_ring_generic cimport \
                                                MPolynomialRing_generic
from sage.rings.polynomial.multi_polynomial cimport MPolynomial
from sage.structure.element cimport MonoidElement

cdef class BooleanPolynomialRing(MPolynomialRing_generic):
    cdef PBRing _R
    cdef public _monom_monoid

cdef class BooleanPolynomial(MPolynomial):
    cdef PBPoly _P

cdef class BooleSet:
    cdef PBSet _S

cdef class CCuddNavigator:
    cdef PBNavigator _N

cdef class DD:
    cdef PBDD _D

cdef class BooleanMonomial(MonoidElement):
    cdef PBMonom _M

cdef class BooleanMonomialIterator:
    cdef PBMonom _obj
    cdef PBMonomIter _iter

cdef class BooleanPolynomialIterator:
    cdef BooleanPolynomial _obj
    cdef PBPolyIter _iter

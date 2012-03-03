
from sage.rings.integer cimport Integer
from sage.rings.rational cimport Rational
from sage.rings.padics.padic_generic_element cimport pAdicGenericElement
import sage.rings.finite_rings.integer_mod
from sage.libs.pari.gen cimport gen as pari_gen
from sage.rings.infinity import infinity

cdef long maxordp = (1L << (sizeof(long) * 8 - 2)) - 1
cdef Integer tmp = PY_NEW(Integer)

include "../../libs/pari/decl.pxi"
include "../../ext/stdsage.pxi"

cdef long get_ordp(x, PowComputer_class prime_pow) except? -10000:
    cdef long k
    cdef Integer value
    cdef GEN pari_tmp
    if PY_TYPE_CHECK(x, Integer):
        if mpz_sgn((<Integer>x).value) == 0:
            return maxordp
        k = mpz_remove(tmp.value, (<Integer>x).value, prime_pow.prime.value)
    elif PY_TYPE_CHECK(x, Rational):
        if mpq_sgn((<Rational>x).value) == 0:
            return maxordp
        k = mpz_remove(tmp.value, mpq_numref((<Rational>x).value), prime_pow.prime.value)
        if k == 0:
            k = -mpz_remove(tmp.value, mpq_denref((<Rational>x).value), prime_pow.prime.value)
    elif PY_TYPE_CHECK(x, pAdicGenericElement) and (<pAdicGenericElement>x)._is_base_elt(prime_pow.prime):
        k = (<pAdicGenericElement>x).valuation_c()
    elif PY_TYPE_CHECK(x, pari_gen):
        pari_tmp = (<pari_gen>x).g
        if typ(pari_tmp) == t_PADIC:
            k = valp(pari_tmp)
        else: # t_INT and t_FRAC were converted before this function
            raise TypeError, "unsupported coercion from pari: only p-adics, integers and rationals allowed"
    elif sage.rings.finite_rings.integer_mod.is_IntegerMod(x):
        value = <Integer>x.lift()
        if mpz_sgn(value.value) == 0:
            return maxordp
        k = mpz_remove(tmp.value, value.value, prime_pow.prime.value)
    else:
        raise RuntimeError
    # Should check for overflow
    return k * prime_pow.e

cdef long get_preccap(x, PowComputer_class prime_pow) except? -10000:
    cdef long k
    cdef Integer prec
    cdef GEN pari_tmp
    if PY_TYPE_CHECK(x, Integer) or PY_TYPE_CHECK(x, Rational):
        return maxordp
    elif PY_TYPE_CHECK(x, pAdicGenericElement) and (<pAdicGenericElement>x)._is_base_elt(prime_pow.prime):
        if (<pAdicGenericElement>x)._is_exact_zero():
            return maxordp
        prec = <Integer>x.precision_absolute()
        k = mpz_get_si(prec.value)
    elif PY_TYPE_CHECK(x, pari_gen):
        pari_tmp = (<pari_gen>x).g
        # since get_ordp has been called typ(x.g) == t_PADIC
        k = valp(pari_tmp) + precp(pari_tmp)
    elif sage.rings.finite_rings.integer_mod.is_IntegerMod(x):
        k = mpz_remove(tmp.value, (<Integer>x.modulus()).value, prime_pow.prime.value)
        if mpz_cmp_ui(tmp.value, 1) != 0:
            raise TypeError, "cannot coerce from the given integer mod ring (not a power of the same prime)"
    else:
        raise RuntimeError
    return k * prime_pow.e

cdef long comb_prec(iprec, long prec) except? -10000:
    if iprec is infinity: return prec
    cdef Integer intprec
    if PY_TYPE_CHECK(iprec, Integer):
        intprec = <Integer>iprec
        if mpz_cmp_si(intprec.value, prec) >= 0:
            return prec
        if mpz_fits_slong_p(intprec.value) == 0:
            raise ValueError("precision overflow")
        return mpz_get_si(intprec.value)
    if isinstance(iprec, int):
        return min(PyInt_AS_LONG(iprec), prec)
    return comb_prec(Integer(iprec), prec)

cdef int _process_args_and_kwds(long *aprec, long *rprec, args, kwds, bint absolute, PowComputer_class prime_pow) except -1:
    """
    This function obtains values for absprec and relprec from a combination of positional and keyword arguments.
    """
    if kwds.has_key("empty"):
        # For backward compatibility
        aprec[0] = 0
        rprec[0] = 0
        return 0
    if len(args) > 2:
        raise TypeError, "too many positional arguments"
    if len(args) == 2:
        if kwds.has_key("relprec"):
            raise TypeError, "_call_with_args() got multiple values for keyword argument 'relprec'"
        relprec = args[1]
    elif kwds.has_key("relprec"):
        relprec = kwds["relprec"]
    else:
        relprec = infinity
    if relprec is not infinity and not PY_TYPE_CHECK(relprec, Integer):
        relprec = Integer(relprec)
    if len(args) >= 1:
        if kwds.has_key("absprec"):
            raise TypeError, "_call_with_args() got multiple values for keyword argument 'absprec'"
        absprec = args[0]
    elif kwds.has_key("absprec"):
        absprec = kwds["absprec"]
    else:
        absprec = infinity
    if absprec is not infinity and not PY_TYPE_CHECK(absprec, Integer):
        absprec = Integer(absprec)
    if absolute:
        aprec[0] = comb_prec(absprec, prime_pow.prec_cap)
        rprec[0] = comb_prec(relprec, maxordp)
    else:
        rprec[0] = comb_prec(relprec, prime_pow.prec_cap)
        aprec[0] = comb_prec(absprec, maxordp)
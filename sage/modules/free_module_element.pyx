r"""
Elements of free modules

AUTHORS:

- William Stein

- Josh Kantor

- Thomas Feulner (2012-11): Added :meth:`FreeModuleElement.hamming_weight` and 
  :meth:`FreeModuleElement_generic_sparse.hamming_weight`

TODO: Change to use a get_unsafe / set_unsafe, etc., structure
exactly like with matrices, since we'll have to define a bunch of
special purpose implementations of vectors easily and
systematically.

EXAMPLES: We create a vector space over `\QQ` and a
subspace of this space.

::

    sage: V = QQ^5
    sage: W = V.span([V.1, V.2])

Arithmetic operations always return something in the ambient space,
since there is a canonical map from `W` to `V` but
not from `V` to `W`.

::

    sage: parent(W.0 + V.1)
    Vector space of dimension 5 over Rational Field
    sage: parent(V.1 + W.0)
    Vector space of dimension 5 over Rational Field
    sage: W.0 + V.1
    (0, 2, 0, 0, 0)
    sage: W.0 - V.0
    (-1, 1, 0, 0, 0)

Next we define modules over `\ZZ` and a finite
field.

::

    sage: K = ZZ^5
    sage: M = GF(7)^5

Arithmetic between the `\QQ` and
`\ZZ` modules is defined, and the result is always
over `\QQ`, since there is a canonical coercion map
to `\QQ`.

::

    sage: K.0 + V.1
    (1, 1, 0, 0, 0)
    sage: parent(K.0 + V.1)
    Vector space of dimension 5 over Rational Field

Since there is no canonical coercion map to the finite field from
`\QQ` the following arithmetic is not defined::

    sage: V.0 + M.0
    Traceback (most recent call last):
    ...
    TypeError: unsupported operand parent(s) for '+': 'Vector space of dimension 5 over Rational Field' and 'Vector space of dimension 5 over Finite Field of size 7'

However, there is a map from `\ZZ` to the finite
field, so the following is defined, and the result is in the finite
field.

::

    sage: w = K.0 + M.0; w
    (2, 0, 0, 0, 0)
    sage: parent(w)
    Vector space of dimension 5 over Finite Field of size 7
    sage: parent(M.0 + K.0)
    Vector space of dimension 5 over Finite Field of size 7

Matrix vector multiply::

    sage: MS = MatrixSpace(QQ,3)
    sage: A = MS([0,1,0,1,0,0,0,0,1])
    sage: V = QQ^3
    sage: v = V([1,2,3])
    sage: v * A
    (2, 1, 3)

TESTS::

    sage: D = 46341
    sage: u = 7
    sage: R = Integers(D)
    sage: p = matrix(R,[[84, 97, 55, 58, 51]])
    sage: 2*p.row(0)
    (168, 194, 110, 116, 102)
"""

import math
import operator

include '../ext/cdefs.pxi'
include '../ext/stdsage.pxi'
import sage.misc.misc as misc
import sage.misc.latex

from sage.structure.sequence import Sequence

from sage.structure.element cimport Element, ModuleElement, RingElement, Vector as element_Vector
from sage.structure.element import canonical_coercion

import sage.rings.arith

from sage.rings.infinity import Infinity
import sage.rings.integer
from sage.rings.integer_ring import ZZ
from sage.rings.real_double import RDF
from sage.rings.complex_double import CDF
from sage.misc.derivative import multi_derivative


# We use some cimports for very quick checking of Integer and Ring
# type to optimize vector(ring,n) for creating the zero vector.
from sage.rings.ring cimport Ring
from sage.rings.integer cimport Integer

# We define our own faster is_Ring since is_Ring in the
# sage.rings.ring module is slow due to it doing an import every time,
# and creating a category.  We should rarely hit the second case
# (is_Ring_slow below).  Note that this function will slightly slow
# down in the very rare case when R is not of type Ring, but it is in
# the category of rings.  But it gives a big speedup for the most
# common case when R is a Ring.
from sage.rings.ring import is_Ring as is_Ring_slow
cdef is_Ring(R):
    return isinstance(R, Ring) or is_Ring_slow(R)

#For the norm function, we cache a Sage integer "one"
__one__ = sage.rings.integer.Integer(1)

def is_FreeModuleElement(x):
    """
    EXAMPLES::

        sage: sage.modules.free_module_element.is_FreeModuleElement(0)
        False
        sage: sage.modules.free_module_element.is_FreeModuleElement(vector([1,2,3]))
        True
    """
    return isinstance(x, FreeModuleElement)

def vector(arg0, arg1=None, arg2=None, sparse=None):
    r"""
    Return a vector or free module element with specified entries.

    CALL FORMATS:

    This constructor can be called in several different ways.
    In each case, ``sparse=True`` or ``sparse=False`` can be
    supplied as an option.  ``free_module_element()`` is an
    alias for ``vector()``.

        1. vector(object)

        2. vector(ring, object)

        3. vector(object, ring)

        4. vector(ring, degree, object)

        5. vector(ring, degree)

        6. vector(numpy_array)

    INPUT:

    -  ``object`` - a list, dictionary, or other
       iterable containing the entries of the vector, including
       any object that is palatable to the ``Sequence`` constructor

    -  ``ring`` - a base ring (or field) for the vector
       space or free module, which contains all of the elements

    -  ``degree`` - an integer specifying the number of
       entries in the vector or free module element

    -  ``numpy_array`` - a NumPy array with the desired entries

    -  ``sparse`` - optional

    In call format 4, an error is raised if the ``degree`` does not match
    the length of ``object`` so this call can provide some safeguards.
    Note however that using this format when ``object`` is a dictionary
    is unlikely to work properly.

    OUTPUT:
   
    An element of the vector space or free module with the given
    base ring and implied or specified dimension or rank,
    containing the specified entries and with correct degree.

    In call format 5, no entries are specified, so the element is
    populated with all zeros.

    If the ``sparse`` option is not supplied, the output will
    generally have a dense representation.  The exception is if
    ``object`` is a dictionary, then the representation will be sparse.

    EXAMPLES::

        sage: v = vector([1,2,3]); v
        (1, 2, 3)
        sage: v.parent()
        Ambient free module of rank 3 over the principal ideal domain Integer Ring
        sage: v = vector([1,2,3/5]); v
        (1, 2, 3/5)
        sage: v.parent()
        Vector space of dimension 3 over Rational Field

    All entries must *canonically* coerce to some common ring::

        sage: v = vector([17, GF(11)(5), 19/3]); v
        Traceback (most recent call last):
        ...
        TypeError: unable to find a common ring for all elements

    ::

        sage: v = vector([17, GF(11)(5), 19]); v
        (6, 5, 8)
        sage: v.parent()
        Vector space of dimension 3 over Finite Field of size 11
        sage: v = vector([17, GF(11)(5), 19], QQ); v
        (17, 5, 19)
        sage: v.parent()
        Vector space of dimension 3 over Rational Field
        sage: v = vector((1,2,3), QQ); v
        (1, 2, 3)
        sage: v.parent()
        Vector space of dimension 3 over Rational Field
        sage: v = vector(QQ, (1,2,3)); v
        (1, 2, 3)
        sage: v.parent()
        Vector space of dimension 3 over Rational Field
        sage: v = vector(vector([1,2,3])); v
        (1, 2, 3)
        sage: v.parent()
        Ambient free module of rank 3 over the principal ideal domain Integer Ring

    You can also use ``free_module_element``, which is
    the same as ``vector``. ::

        sage: free_module_element([1/3, -4/5])
        (1/3, -4/5)

    We make a vector mod 3 out of a vector over `\ZZ`. ::

        sage: vector(vector([1,2,3]), GF(3))
        (1, 2, 0)

    The degree of a vector may be specified::

        sage: vector(QQ, 4, [1,1/2,1/3,1/4])
        (1, 1/2, 1/3, 1/4)

    But it is an error if the degree and size of the list of entries
    are mismatched::

        sage: vector(QQ, 5, [1,1/2,1/3,1/4])
        Traceback (most recent call last):
        ...
        ValueError: incompatible degrees in vector constructor

    Providing no entries populates the vector with zeros, but of course,
    you must specify the degree since it is not implied.  Here we use a
    finite field as the base ring. ::

        sage: w = vector(FiniteField(7), 4); w
        (0, 0, 0, 0)
        sage: w.parent()
        Vector space of dimension 4 over Finite Field of size 7
        
    The fastest method to construct a zero vector is to call the
    :meth:`~sage.modules.free_module.FreeModule_generic.zero_vector`
    method directly on a free module or vector space, since
    vector(...)  must do a small amount of type checking.  Almost as
    fast as the ``zero_vector()`` method is the
    :func:`~sage.modules.free_module_element.zero_vector` constructor,
    which defaults to the integers.  ::

        sage: vector(ZZ, 5)          # works fine
        (0, 0, 0, 0, 0)
        sage: (ZZ^5).zero_vector()   # very tiny bit faster
        (0, 0, 0, 0, 0)
        sage: zero_vector(ZZ, 5)     # similar speed to vector(...)
        (0, 0, 0, 0, 0)
        sage: z = zero_vector(5); z
        (0, 0, 0, 0, 0)
        sage: z.parent()
        Ambient free module of rank 5 over
        the principal ideal domain Integer Ring

    Here we illustrate the creation of sparse vectors by using a
    dictionary. ::

        sage: vector({1:1.1, 3:3.14})
        (0.000000000000000, 1.10000000000000, 0.000000000000000, 3.14000000000000)

    With no degree given, a dictionary of entries implicitly declares a
    degree by the largest index (key) present.  So you can provide a
    terminal element (perhaps a zero?) to set the degree.  But it is probably safer
    to just include a degree in your construction.  ::

        sage: v = vector(QQ, {0:1/2, 4:-6, 7:0}); v
        (1/2, 0, 0, 0, -6, 0, 0, 0)
        sage: v.degree()
        8
        sage: v.is_sparse()
        True
        sage: w = vector(QQ, 8, {0:1/2, 4:-6})
        sage: w == v
        True

    It is an error to specify a negative degree. ::

        sage: vector(RR, -4, [1.0, 2.0, 3.0, 4.0])
        Traceback (most recent call last):
        ...
        ValueError: cannot specify the degree of a vector as a negative integer (-4)
        
    It is an error to create a zero vector but not provide
    a ring as the first argument.  ::
    
        sage: vector('junk', 20)
        Traceback (most recent call last):
        ...
        TypeError: first argument must be base ring of zero vector, not junk
        
    And it is an error to specify an index in a dictionary
    that is greater than or equal to a requested degree. ::

        sage: vector(ZZ, 10, {3:4, 7:-2, 10:637})
        Traceback (most recent call last):
        ...
        ValueError: dictionary of entries has a key (index) exceeding the requested degree

    Any 1 dimensional numpy array of type float or complex may be
    passed to vector. The result will be a vector in the appropriate
    dimensional vector space over the real double field or the complex
    double field. The data in the array must be contiguous so
    column-wise slices of numpy matrices will raise an exception. ::

        sage: import numpy
        sage: x=numpy.random.randn(10)
        sage: y=vector(x)
        sage: v=numpy.random.randn(10)*numpy.complex(0,1)
        sage: w=vector(v)

    If any of the arguments to vector have Python type int, long, real,
    or complex, they will first be coerced to the appropriate Sage
    objects. This fixes trac #3847. ::

        sage: v = vector([int(0)]); v
        (0)
        sage: v[0].parent()
        Integer Ring
        sage: v = vector(range(10)); v
        (0, 1, 2, 3, 4, 5, 6, 7, 8, 9)
        sage: v[3].parent()
        Integer Ring
        sage: v = vector([float(23.4), int(2), complex(2+7*I), long(1)]); v
        (23.4, 2.0, 2.0 + 7.0*I, 1.0)
        sage: v[1].parent()
        Complex Double Field

    If the argument is a vector, it doesn't change the base ring. This 
    fixes trac #6643. ::

        sage: K.<sqrt3> = QuadraticField(3)
        sage: u = vector(K, (1/2, sqrt3/2) )
        sage: vector(u).base_ring()
        Number Field in sqrt3 with defining polynomial x^2 - 3
        sage: v = vector(K, (0, 1) )
        sage: vector(v).base_ring()
        Number Field in sqrt3 with defining polynomial x^2 - 3

    Constructing a vector from a numpy array behaves as expected::

        sage: import numpy
        sage: a=numpy.array([1,2,3])
        sage: v=vector(a); v
        (1, 2, 3)
        sage: parent(v)
        Ambient free module of rank 3 over the principal ideal domain Integer Ring

    Complex numbers can be converted naturally to a sequence of length 2.  And
    then to a vector.  ::

        sage: c = CDF(2 + 3*I)
        sage: v = vector(c); v
        (2.0, 3.0)

    A generator, or other iterable, may also be supplied as input.  Anything
    that can be converted to a :class:`~sage.structure.sequence.Sequence` is
    a possible input.  ::

        sage: type(i^2 for i in range(3))
        <type 'generator'>
        sage: v = vector(i^2 for i in range(3)); v
        (0, 1, 4)

    An empty list, without a ring given, will default to the integers. ::

        sage: x = vector([]); x
        ()
        sage: x.parent()
        Ambient free module of rank 0 over the principal ideal domain Integer Ring
    """
    # We first efficiently handle the important special case of the zero vector
    # over a ring. See trac 11657.
    # !! PLEASE DO NOT MOVE THIS CODE LOWER IN THIS FUNCTION !!
    if arg2 is None and is_Ring(arg0) and (isinstance(arg1, (int, long, Integer))):
        return (arg0**arg1).zero_vector()

    # WARNING TO FUTURE OPTIMIZERS: The following two hasattr's take
    # quite a significant amount of time.
    if hasattr(arg0, '_vector_'):
        return arg0._vector_(arg1)

    if hasattr(arg1, '_vector_'):
        return arg1._vector_(arg0)

    # consider a possible degree specified in second argument
    degree = None
    maxindex = None
    if sage.rings.integer.is_Integer(arg1) or isinstance(arg1,(int,long)):
        if arg1 < 0:
            raise ValueError("cannot specify the degree of a vector as a negative integer (%s)" % arg1)
        if isinstance(arg2, dict):
            maxindex = max([-1]+[index for index in arg2])
            if not maxindex < arg1:
                raise ValueError("dictionary of entries has a key (index) exceeding the requested degree")
        # arg1 is now a legitimate degree
        # With no arg2, we can try to return a zero vector
        #   else we size-check arg2 and slide it into arg1
        degree = arg1
        if arg2 is None:
            if not is_Ring(arg0):
                msg = "first argument must be base ring of zero vector, not {0}"
                raise TypeError(msg.format(arg0))
        else:
            if not isinstance(arg2, dict) and len(arg2) != degree:
                raise ValueError("incompatible degrees in vector constructor")
            arg1 = arg2

    # Analyze arg0 and arg1 to create a ring (R) and entries (v)
    if is_Ring(arg0):
        R = arg0
        v = arg1
    elif is_Ring(arg1):
        R = arg1
        v = arg0
    else:
        v = arg0
        R = None

    from numpy import ndarray
    from free_module import VectorSpace
    if isinstance(v,ndarray):
        if len(v.shape)==1:
            if str(v.dtype).count('float')==1:
                V=VectorSpace(RDF,v.shape[0])
                import vector_real_double_dense
                _v=vector_real_double_dense.Vector_real_double_dense(V, v)
                return _v
            if str(v.dtype).count('complex')==1:
                V=VectorSpace(CDF,v.shape[0])
                import vector_complex_double_dense
                _v=vector_complex_double_dense.Vector_complex_double_dense(V, v)
                return _v

    if isinstance(v, dict):
        if degree is None:
            degree = max([-1]+[index for index in v])+1
        if sparse is None:
            sparse = True
    else:
        degree = None
        if sparse is None:
            sparse = False

    v, R = prepare(v, R, degree)

    if sparse:
        import free_module  # slow -- can we improve
        return free_module.FreeModule(R, len(v), sparse=True)(v)
    else:
        return (R**len(v))(v)

free_module_element = vector

def prepare(v, R, degree=None):
    r"""
    Converts an object describing elements of a vector into a list of entries in a common ring.

    INPUT:

    - ``v`` - a dictionary with non-negative integers as keys,
      or a list or other object that can be converted by the ``Sequence``
      constructor
    - ``R`` - a ring containing all the entries, possibly given as ``None``
    - ``degree`` -  a requested size for the list when the input is a dictionary,
      otherwise ignored

    OUTPUT:

    A pair.

    The first item is a list of the values specified in the object ``v``.
    If the object is a dictionary , entries are placed in the list
    according to the indices that were their keys in the dictionary,
    and the remainder of the entries are zero.  The value of
    ``degree`` is assumed to be larger than any index provided
    in the dictionary and will be used as the number of entries
    in the returned list.

    The second item returned is a ring that contains all of
    the entries in the list. If ``R`` is given, the entries
    are coerced in.  Otherwise a common ring is found. For
    more details, see the
    :class:`~sage.structure.sequence.Sequence` object.  When ``v``
    has no elements and ``R`` is ``None``, the ring returned is
    the integers.


    EXAMPLES::

        sage: from sage.modules.free_module_element import prepare
        sage: prepare([1,2/3,5],None)
        ([1, 2/3, 5], Rational Field)

        sage: prepare([1,2/3,5],RR)
        ([1.00000000000000, 0.666666666666667, 5.00000000000000], Real Field with 53 bits of precision)

        sage: prepare({1:4, 3:-2}, ZZ, 6)
        ([0, 4, 0, -2, 0, 0], Integer Ring)

        sage: prepare({3:1, 5:3}, QQ, 6)
        ([0, 0, 0, 1, 0, 3], Rational Field)

        sage: prepare([1,2/3,'10',5],RR)
        ([1.00000000000000, 0.666666666666667, 10.0000000000000, 5.00000000000000], Real Field with 53 bits of precision)

        sage: prepare({},QQ, 0)
        ([], Rational Field)

        sage: prepare([1,2/3,'10',5],None)
        Traceback (most recent call last):
        ...
        TypeError: unable to find a common ring for all elements

    Some objects can be converted to sequences even if they are not always
    thought of as sequences.  ::

        sage: c = CDF(2+3*I)
        sage: prepare(c, None)
        ([2.0, 3.0], Real Double Field)

    This checks a bug listed at Trac #10595.  Without good evidence for a ring, the default
    is the integers. ::
        
        sage: prepare([], None)
        ([], Integer Ring)
    """
    if isinstance(v, dict):
        # convert to a list
        X = [0]*degree
        for key, value in v.iteritems():
            X[key] = value
        v = X
    # convert to a Sequence over common ring
    # default to ZZ on an empty list
    if R is None:
        try:
            if len(v) == 0:
                R = ZZ
        except TypeError:
            pass
    v = Sequence(v, universe=R, use_sage_types=True)
    ring = v.universe()
    if not is_Ring(ring):
        raise TypeError("unable to find a common ring for all elements")
    return v, ring

def zero_vector(arg0, arg1=None):
    r"""
    Returns a vector or free module element with a specified number of zeros.

    CALL FORMATS:

        1. zero_vector(degree)

        2. zero_vector(ring, degree)

    INPUT:

    - ``degree`` - the number of zero entries in the vector or
      free module element

    - ``ring`` - default ``ZZ`` - the base ring of the vector
      space or module containing the constructed zero vector

    OUTPUT:

    A vector or free module element with ``degree`` entries,
    all equal to zero and belonging to the ring if specified.
    If no ring is given, a free module element over ``ZZ``
    is returned.

    EXAMPLES:

    A zero vector over the field of rationals. ::

        sage: v = zero_vector(QQ, 5); v
        (0, 0, 0, 0, 0)
        sage: v.parent()
        Vector space of dimension 5 over Rational Field

    A free module zero element. ::

        sage: w = zero_vector(Integers(6), 3); w
        (0, 0, 0)
        sage: w.parent()
        Ambient free module of rank 3 over Ring of integers modulo 6

    If no ring is given, the integers are used. ::

        sage: u = zero_vector(9); u
        (0, 0, 0, 0, 0, 0, 0, 0, 0)
        sage: u.parent()
        Ambient free module of rank 9 over the principal ideal domain Integer Ring

    Non-integer degrees produce an error. ::

        sage: zero_vector(5.6)
        Traceback (most recent call last):
        ...
        TypeError: Attempt to coerce non-integral RealNumber to Integer

    Negative degrees also give an error. ::

        sage: zero_vector(-3)
        Traceback (most recent call last):
        ...
        ValueError: rank (=-3) must be nonnegative

    Garbage instead of a ring will be recognized as such. ::

        sage: zero_vector(x^2, 5)
        Traceback (most recent call last):
        ...
        TypeError: first argument must be a ring
    """
    if arg1 is None:
        # default to a zero vector over the integers (ZZ) if no ring given
        return (ZZ**arg0).zero_vector()
    if is_Ring(arg0):
        return (arg0**arg1).zero_vector()
    raise TypeError("first argument must be a ring")

def random_vector(ring, degree=None, *args, **kwds):
    r"""
    Returns a vector (or module element) with random entries.

    INPUT:

    - ring - default: ``ZZ`` - the base ring for the entries
    - degree - a non-negative integer for the number of entries in the vector
    - sparse - default: ``False`` - whether to use a sparse implementation
    - args, kwds - additional arguments and keywords are passed
      to the ``random_element()`` method of the ring

    OUTPUT:

    A vector, or free module element, with ``degree`` elements
    from ``ring``, chosen randomly from the ring according to
    the ring's ``random_element()`` method.

    .. note::
        See below for examples of how random elements are
        generated by some common base rings.

    EXAMPLES:

    First, module elements over the integers.
    The default distribution is tightly clustered around -1, 0, 1.
    Uniform distributions can be specified by giving bounds, though
    the upper bound is never met.  See
    :meth:`sage.rings.integer_ring.IntegerRing_class.random_element`
    for several other variants. ::

        sage: random_vector(10)
        (-8, 2, 0, 0, 1, -1, 2, 1, -95, -1)

        sage: sorted(random_vector(20))
        [-12, -6, -4, -4, -2, -2, -2, -1, -1, -1, 0, 0, 0, 0, 0, 1, 1, 1, 4, 5]

        sage: random_vector(ZZ, 20, x=4)
        (2, 0, 3, 0, 1, 0, 2, 0, 2, 3, 0, 3, 1, 2, 2, 2, 1, 3, 2, 3)

        sage: random_vector(ZZ, 20, x=-20, y=100)
        (43, 47, 89, 31, 56, -20, 23, 52, 13, 53, 49, -12, -2, 94, -1, 95, 60, 83, 28, 63)

        sage: random_vector(ZZ, 20, distribution="1/n")
        (0, -1, -2, 0, -1, -2, 0, 0, 27, -1, 1, 1, 0, 2, -1, 1, -1, -2, -1, 3)

    If the ring is not specified, the default is the integers, and
    parameters for the random distribution may be passed without using
    keywords.  This is a random vector with 20 entries uniformly distributed
    between -20 and 100.  ::

        sage: random_vector(20, -20, 100)
        (70, 19, 98, 2, -18, 88, 36, 66, 76, 52, 82, 99, 55, -17, 82, -15, 36, 28, 79, 18)

    Now over the rationals.  Note that bounds on the numerator and
    denominator may be specified.  See
    :meth:`sage.rings.rational_field.RationalField.random_element`
    for documentation. ::

        sage: random_vector(QQ, 10)
        (0, -1, -4/3, 2, 0, -13, 2/3, 0, -4/5, -1)

        sage: random_vector(QQ, 10, num_bound = 15, den_bound = 5)
        (-12/5, 9/4, -13/3, -1/3, 1, 5/4, 4, 1, -15, 10/3)

    Inexact rings may be used as well.  The reals have
    uniform distributions, with the range `(-1,1)` as
    the default.  More at:
    :meth:`sage.rings.real_mpfr.RealField_class.random_element` ::

        sage: random_vector(RR, 5)
        (0.248997268533725, -0.112200126330480, 0.776829203293064, -0.899146461031406, 0.534465018743125)

        sage: random_vector(RR, 5, min = 8, max = 14)
        (8.43260944052606, 8.34129413391087, 8.92391495103829, 11.5784799413416, 11.0973561568002)

    Any ring with a ``random_element()`` method may be used. ::

        sage: F = FiniteField(23)
        sage: hasattr(F, 'random_element')
        True
        sage: random_vector(F, 10)
        (21, 6, 5, 2, 6, 2, 18, 9, 9, 7)

    The default implementation is a dense representation, equivalent to
    setting ``sparse=False``. ::

        sage: v = random_vector(10)
        sage: v.is_sparse()
        False

        sage: w = random_vector(ZZ, 20, sparse=True)
        sage: w.is_sparse()
        True

    Inputs get checked before constructing the vector. ::

        sage: random_vector('junk')
        Traceback (most recent call last):
        ...
        TypeError: degree of a random vector must be an integer, not None

        sage: random_vector('stuff', 5)
        Traceback (most recent call last):
        ...
        TypeError: elements of a vector, or module element, must come from a ring, not stuff

        sage: random_vector(ZZ, -9)
        Traceback (most recent call last):
        ...
        ValueError: degree of a random vector must be non-negative, not -9
    """
    if sage.rings.integer.is_Integer(ring) or isinstance(ring,(int,long)):
        if not degree is None:
            arglist = list(args)
            arglist.insert(0, degree)
            args = tuple(arglist)
        degree = ring
        ring = ZZ
    if not (sage.rings.integer.is_Integer(degree) or isinstance(degree,(int,long))):
        raise TypeError("degree of a random vector must be an integer, not %s" % degree)
    if degree < 0:
        raise ValueError("degree of a random vector must be non-negative, not %s" % degree)
    if not is_Ring(ring):
        raise TypeError("elements of a vector, or module element, must come from a ring, not %s" % ring)
    if not hasattr(ring, "random_element"):
        raise AttributeError("cannot create a random vector since there is no random_element() method for %s" % ring )
    sparse = kwds.pop('sparse', False)
    entries = [ring.random_element(*args, **kwds) for _ in range(degree)]
    return vector(ring, degree, entries, sparse)

cdef class FreeModuleElement(element_Vector):   # abstract base class
    """
    An element of a generic free module.
    """
    def __init__(self, parent):
        """
        EXAMPLES::

            sage: v = sage.modules.free_module_element.FreeModuleElement(QQ^3)
            sage: type(v)
            <type 'sage.modules.free_module_element.FreeModuleElement'>
        """
        self._parent = parent
        self._degree = parent.degree()
        self._is_mutable = 1

    def _giac_init_(self):
        """
        EXAMPLES::

            sage: v = vector(ZZ, 4, range(4))               #optional - giac
            sage: giac(v)+v                                #optional -  giac
            [0,2,4,6]

        ::

            sage: v = vector(QQ, 3, [2/3, 0, 5/4])          #optional
            sage: giac(v)                                  #optional
            [2/3,0,5/4]

        ::

            sage: P.<x> = ZZ[]                                       #optional
            sage: v = vector(P, 3, [x^2 + 2, 2*x + 1, -2*x^2 + 4*x]) #optional
            sage: giac(v)                                           #optional
            [x^2+2,2*x+1,-2*x^2+4*x]
        """
        return self.list()

    def _magma_init_(self, magma):
        r"""
        Convert self to Magma.
        
        EXAMPLES::
        
            sage: F = FreeModule(ZZ, 2, inner_product_matrix=matrix(ZZ, 2, 2, [1, 0, 0, -1]))
            sage: v = F([1, 2])
            sage: M = magma(v); M # optional - magma
            (1 2)
            sage: M.Type() # optional - magma
            ModTupRngElt
            sage: M.Parent() # optional - magma
            Full RSpace of degree 2 over Integer Ring
            Inner Product Matrix:
            [ 1  0]
            [ 0 -1]
            sage: M.sage() # optional - magma
            (1, 2)
            sage: M.sage() == v # optional - magma
            True
            sage: M.sage().parent() is v.parent() # optional - magma
            True
        
        ::
        
            sage: v = vector(QQ, [1, 2, 5/6])
            sage: M = magma(v); M # optional - magma
            (  1   2 5/6)
            sage: M.Type() # optional - magma
            ModTupFldElt
            sage: M.Parent() # optional - magma
            Full Vector space of degree 3 over Rational Field
            sage: M.sage() # optional - magma
            (1, 2, 5/6)
            sage: M.sage() == v # optional - magma
            True
            sage: M.sage().parent() is v.parent() # optional - magma
            True
        """
        # Get a reference to Magma version of parent.   
        R = magma(self.parent())
        # Get list of coefficients.
        v = ','.join([a._magma_init_(magma) for a in self.list()])
        return '%s![%s]' % (R.name(), v)

    def __hash__(self):
        """
        Return hash of this vector.  Only mutable vectors are hashable. 
        
        EXAMPLES::
            sage: v = vector([1,2/3,pi])
            sage: v.__hash__()
            Traceback (most recent call last):
            ...
            TypeError: mutable vectors are unhashable
            sage: v.set_immutable()
            sage: v.__hash__()   # random output
        """
        if self._is_mutable:
            raise TypeError("mutable vectors are unhashable")
        return hash(tuple(self))

    def _vector_(self, R=None):
        r"""
        Return self as a vector.

        EXAMPLES::
        
            sage: v = vector(ZZ, [2, 12, 22])
            sage: vector(v)
            (2, 12, 22)
            sage: vector(GF(7), v)
            (2, 5, 1)
            sage: vector(v, ZZ['x', 'y'])
            (2, 12, 22)

            sage: vector(vector((1, 6.8)))
            (1.00000000000000, 6.80000000000000)
            sage: vector(vector(SR, (1, sqrt(2)) ) )
            (1, sqrt(2))
        """
        if R is None:
            R = self.base_ring()
        return self.change_ring(R)

    def _matrix_(self, R=None):
        r"""
        Return self as a row matrix.

        EXAMPLES::
        
            sage: v = vector(ZZ, [2, 12, 22])
            sage: vector(v)
            (2, 12, 22)
            sage: vector(GF(7), v)
            (2, 5, 1)
            sage: vector(v, ZZ['x', 'y'])
            (2, 12, 22)
        """
        if R is None:
            R = self.base_ring()
        sparse = self.is_sparse()
        from sage.matrix.constructor import matrix
        return matrix(R, [list(self)], sparse=sparse)

    def _sage_input_(self, sib, coerce):
        r"""
        Produce an expression which will reproduce this value when evaluated.
        
        EXAMPLES::
        
            sage: sage_input(vector(RR, [pi, e, 0.5]), verify=True)
            # Verified
            vector(RR, [3.1415926535897931, 2.7182818284590451, 0.5])
            sage: sage_input(vector(GF(5), [1, 2, 3, 4, 5]), verify=True)
            # Verified
            vector(GF(5), [1, 2, 3, 4, 0])
            sage: sage_input(vector([0, 0, 0, 1, 0, 0, 0], sparse=True), verify=True)
            # Verified
            vector(ZZ, {3:1, 6:0})
            sage: sage_input(vector(ZZ, []), verify=True)
            # Verified
            vector(ZZ, [])
            sage: sage_input(vector(RealField(27), [], sparse=True), verify=True)
            # Verified
            vector(RealField(27), {})
            sage: from sage.misc.sage_input import SageInputBuilder
            sage: vector(ZZ, [42, 389])._sage_input_(SageInputBuilder(), False)
            {call: {atomic:vector}({atomic:ZZ}, {list: ({atomic:42}, {atomic:389})})}
            sage: vector(RDF, {1:pi, 1000:e})._sage_input_(SageInputBuilder(), False)
            {call: {atomic:vector}({atomic:RDF}, {dict: {{atomic:1}:{atomic:3.1415926535897931}, {atomic:1000}:{atomic:2.718281828459045...}}})}
        """
        # Not a lot of room for prettiness here.
        # We always specify the ring, because that lets us use coerced=2
        # on the elements, which is sometimes much prettier than
        # the coerced=False we would get otherwise.
        if self.is_sparse_c():
            items = [(n, sib(e, 2))
                     for n,e in self.dict().items()]
            items.sort()
            if len(self):
                # we may need to add an extra element on the end to
                # set the size.  (There doesn't seem to be a better way
                # to do it.)
                if len(items) == 0 or len(self)-1 > items[-1][0]:
                    items.append((len(self)-1, sib.int(0)))
            items_dict = sib.dict([(sib.int(n), e) for n,e in items])

            return sib.name('vector')(self.base_ring(), items_dict)
        else:
            return sib.name('vector')(self.base_ring(),
                                      [sib(e, 2) for e in self])

    def _numerical_approx(self, prec=None, digits=None):
        r"""
        Implements numerical approximation of a free module element
        by calling the ``n()`` method on all of its entries.

        EXAMPLES::

            sage: v = vector(RealField(212), [1,2,3])
            sage: v.N()
            (1.00000000000000, 2.00000000000000, 3.00000000000000)
            sage: _.parent()
            Vector space of dimension 3 over Real Field with 53 bits of precision
            sage: numerical_approx(v)
            (1.00000000000000, 2.00000000000000, 3.00000000000000)
            sage: _.parent()
            Vector space of dimension 3 over Real Field with 53 bits of precision
            sage: v.n(prec=75)
            (1.000000000000000000000, 2.000000000000000000000, 3.000000000000000000000)
            sage: _.parent()
            Vector space of dimension 3 over Real Field with 75 bits of precision
            sage: numerical_approx(v, digits=3)
            (1.00, 2.00, 3.00)
            sage: _.parent()
            Vector space of dimension 3 over Real Field with 14 bits of precision

        Both functional and object-oriented usage is possible.  ::
            
            sage: u = vector(QQ, [1/2, 1/3, 1/4])
            sage: u.n()
            (0.500000000000000, 0.333333333333333, 0.250000000000000)            
            sage: u.N()
            (0.500000000000000, 0.333333333333333, 0.250000000000000)
            sage: u.numerical_approx()
            (0.500000000000000, 0.333333333333333, 0.250000000000000)
            sage: n(u)
            (0.500000000000000, 0.333333333333333, 0.250000000000000)
            sage: N(u)
            (0.500000000000000, 0.333333333333333, 0.250000000000000)
            sage: numerical_approx(u)
            (0.500000000000000, 0.333333333333333, 0.250000000000000)

        Precision (bits) and digits (decimal) may be specified.
        When both are given, ``prec`` wins.  ::

            sage: u = vector(QQ, [1/2, 1/3, 1/4])
            sage: n(u, prec=15)
            (0.5000, 0.3333, 0.2500)
            sage: n(u, digits=5)
            (0.50000, 0.33333, 0.25000)
            sage: n(u, prec=30, digits=100)
            (0.50000000, 0.33333333, 0.25000000)

        These are some legacy doctests that were part of various specialized
        versions of the numerical approximation routine that were removed as
        part of :trac:`12195`.  ::

            sage: v = vector(ZZ, [1,2,3])
            sage: v.n()
            (1.00000000000000, 2.00000000000000, 3.00000000000000)
            sage: _.parent()
            Vector space of dimension 3 over Real Field with 53 bits of precision
            sage: v.n(prec=75)
            (1.000000000000000000000, 2.000000000000000000000, 3.000000000000000000000)
            sage: _.parent()
            Vector space of dimension 3 over Real Field with 75 bits of precision

            sage: v = vector(RDF, [1,2,3])
            sage: v.n()
            (1.00000000000000, 2.00000000000000, 3.00000000000000)
            sage: _.parent()
            Vector space of dimension 3 over Real Field with 53 bits of precision
            sage: v.n(prec=75)
            (1.000000000000000000000, 2.000000000000000000000, 3.000000000000000000000)
            sage: _.parent()
            Vector space of dimension 3 over Real Field with 75 bits of precision

            sage: v = vector(CDF, [1,2,3])
            sage: v.n()
            (1.00000000000000, 2.00000000000000, 3.00000000000000)
            sage: _.parent()
            Vector space of dimension 3 over Complex Field with 53 bits of precision
            sage: v.n(prec=75)
            (1.000000000000000000000, 2.000000000000000000000, 3.000000000000000000000)
            sage: _.parent()
            Vector space of dimension 3 over Complex Field with 75 bits of precision

            sage: v = vector(Integers(8), [1,2,3])
            sage: v.n()
            (1.00000000000000, 2.00000000000000, 3.00000000000000)
            sage: _.parent()
            Vector space of dimension 3 over Real Field with 53 bits of precision
            sage: v.n(prec=75)
            (1.000000000000000000000, 2.000000000000000000000, 3.000000000000000000000)
            sage: _.parent()
            Vector space of dimension 3 over Real Field with 75 bits of precision

            sage: v = vector(QQ, [1,2,3])
            sage: v.n()
            (1.00000000000000, 2.00000000000000, 3.00000000000000)
            sage: _.parent()
            Vector space of dimension 3 over Real Field with 53 bits of precision
            sage: v.n(prec=75)
            (1.000000000000000000000, 2.000000000000000000000, 3.000000000000000000000)
            sage: _.parent()
            Vector space of dimension 3 over Real Field with 75 bits of precision

        TESTS:

        Sparse vectors have a similar method that works efficiently for
        the sparse case.  We test that it is working as it should.  ::

            sage: v = vector(QQ, [1/2, 0, 0, 1/3, 0, 0, 0, 1/4], sparse=True)
            sage: u = v.numerical_approx(digits=4)
            sage: u.is_sparse()
            True
            sage: u
            (0.5000, 0.0000, 0.0000, 0.3333, 0.0000, 0.0000, 0.0000, 0.2500)
        """
        return vector([e.n(prec, digits) for e in self])

    def transpose(self):
        r"""
        Return self as a column matrix.

        .. note::

            The ``transpose()`` method has been deprecated as of Sage 4.6.2,
            in favor of the :meth:`column` method which is functionally identical.

        EXAMPLES::
        
            sage: v = vector(ZZ, [2, 12, 22])
            sage: transpose(vector(v))
            doctest:...: DeprecationWarning: The transpose() method for vectors has been deprecated, use column() instead
            (or check to see if you have a vector when you really want a matrix)
            See http://trac.sagemath.org/10541 for details.
            [ 2]
            [12]
            [22]
        
        ::
        
            sage: transpose(vector(GF(7), v))
            [2]
            [5]
            [1]
        
        ::
        
            sage: transpose(vector(v, ZZ['x', 'y']))
            [ 2]
            [12]
            [22]
        """
        from sage.misc.superseded import deprecation
        deprecation(10541, 'The transpose() method for vectors has been deprecated, use column() instead\n(or check to see if you have a vector when you really want a matrix)')
        return self._matrix_().transpose()

    def row(self):
        r"""
        Return a matrix with a single row and the same entries as the vector ``self``.

        OUTPUT:

        A matrix over the same ring as the vector (or free module element), with
        a single row.  The entries of the row are identical to those of the vector,
        and in the same order.

        EXAMPLES::

            sage: v = vector(ZZ, [1,2,3])
            sage: w = v.row(); w
            [1 2 3]
            sage: w.parent()
            Full MatrixSpace of 1 by 3 dense matrices over Integer Ring

            sage: x = vector(FiniteField(13), [2,4,8,16])
            sage: x.row()
            [2 4 8 3]

        There is more than one way to get one-row matrix from a vector,
        but the ``row`` method is more efficient than making a column and
        then taking a transpose.  Notice that supplying a vector to the
        matrix constructor demonstrates Sage's preference for rows. ::

            sage: x = vector(RDF, [sin(i*pi/20) for i in range(10)])
            sage: x.row() == matrix(x)
            True
            sage: x.row() == x.column().transpose()
            True

        Sparse or dense implementations are preserved. ::

            sage: d = vector(RR, [1.0, 2.0, 3.0])
            sage: s = vector(CDF, {2:5.0+6.0*I})
            sage: dm = d.row()
            sage: sm = s.row()
            sage: all([d.is_dense(), dm.is_dense(), s.is_sparse(), sm.is_sparse()])
            True

        TESTS:

        The :meth:`~sage.matrix.matrix1.Matrix.row` method will return
        a specified row of a matrix as a vector.  So here are a couple
        of round-trips. ::

            sage: A = matrix(ZZ, [[1,2,3]])
            sage: A == A.row(0).row()
            True
            sage: v = vector(ZZ, [4,5,6])
            sage: v == v.row().row(0)
            True

        And a very small corner case. ::

            sage: v = vector(ZZ, [])
            sage: w = v.row()
            sage: w.parent()
            Full MatrixSpace of 1 by 0 dense matrices over Integer Ring
        """
        return self._matrix_(R=None)

    def column(self):
        r"""
        Return a matrix with a single column and the same entries as the vector ``self``.

        OUTPUT:

        A matrix over the same ring as the vector (or free module element), with
        a single column.  The entries of the column are identical to those of the
        vector, and in the same order.

        EXAMPLES::

            sage: v = vector(ZZ, [1,2,3])
            sage: w = v.column(); w
            [1]
            [2]
            [3]
            sage: w.parent()
            Full MatrixSpace of 3 by 1 dense matrices over Integer Ring

            sage: x = vector(FiniteField(13), [2,4,8,16])
            sage: x.column()
            [2]
            [4]
            [8]
            [3]

        There is more than one way to get one-column matrix from a vector.
        The ``column`` method is about equally efficient to making a row and
        then taking a transpose.  Notice that supplying a vector to the
        matrix constructor demonstrates Sage's preference for rows. ::

            sage: x = vector(RDF, [sin(i*pi/20) for i in range(10)])
            sage: x.column() == matrix(x).transpose()
            True
            sage: x.column() == x.row().transpose()
            True

        Sparse or dense implementations are preserved. ::

            sage: d = vector(RR, [1.0, 2.0, 3.0])
            sage: s = vector(CDF, {2:5.0+6.0*I})
            sage: dm = d.column()
            sage: sm = s.column()
            sage: all([d.is_dense(), dm.is_dense(), s.is_sparse(), sm.is_sparse()])
            True

        TESTS:

        The :meth:`~sage.matrix.matrix1.Matrix.column` method will return
        a specified column of a matrix as a vector.  So here are a couple
        of round-trips. ::

            sage: A = matrix(ZZ, [[1],[2],[3]])
            sage: A == A.column(0).column()
            True
            sage: v = vector(ZZ, [4,5,6])
            sage: v == v.column().column(0)
            True

        And a very small corner case. ::

            sage: v = vector(ZZ, [])
            sage: w = v.column()
            sage: w.parent()
            Full MatrixSpace of 0 by 1 dense matrices over Integer Ring
        """
        return self._matrix_(R=None).transpose()

    def _hash(self):
        """
        Return hash of an immutable form of self (works even if self
        is mutable).

        EXAMPLES::
            sage: v = vector([1,2/3,pi])
            sage: v.__hash__()
            Traceback (most recent call last):
            ...
            TypeError: mutable vectors are unhashable
            sage: v._hash()  # random output
        """
        return hash(tuple(list(self)))

    def __copy__(self):
        """
        Make a copy of this vector.
        
        EXAMPLES::
        
            sage: v = vector([1..5]); v
            (1, 2, 3, 4, 5)
            sage: w = copy(v)
            sage: v == w
            True
            sage: v is w
            False
        
        ::
        
            sage: v = vector([1..5], sparse=True); v
            (1, 2, 3, 4, 5)
            sage: copy(v)
            (1, 2, 3, 4, 5)
        """
        if self.is_sparse():
            return self.parent()(self.dict())
        else:
            return self.parent()(self.list())

    def subs(self, in_dict=None, **kwds):
        """
        EXAMPLES::
        
            sage: var('a,b,d,e')
            (a, b, d, e)
            sage: v = vector([a, b, d, e])
            sage: v.substitute(a=1)
            (1, b, d, e)
            sage: v.subs(a=b, b=d)
            (b, d, d, e)
        """
        return self.parent()([ a.subs(in_dict, **kwds) for a in self.list() ])

    def set_immutable(self):
        """
        Make this vector immutable. This operation can't be undone.
        
        EXAMPLES::
        
            sage: v = vector([1..5]); v
            (1, 2, 3, 4, 5)
            sage: v[1] = 10
            sage: v.set_immutable()
            sage: v[1] = 10
            Traceback (most recent call last):
            ...
            ValueError: vector is immutable; please change a copy instead (use copy())
        """
        self._is_mutable = 0

    def is_mutable(self):
        """
        Return True if this vector is mutable, i.e., the entries can be
        changed.
        
        EXAMPLES::
        
            sage: v = vector(QQ['x,y'], [1..5]); v.is_mutable()
            True
            sage: v.set_immutable()
            sage: v.is_mutable()
            False
        """
        return self._is_mutable

    def is_immutable(self):
        """
        Return True if this vector is immutable, i.e., the entries cannot
        be changed.
        
        EXAMPLES::
        
            sage: v = vector(QQ['x,y'], [1..5]); v.is_immutable()
            False
            sage: v.set_immutable()
            sage: v.is_immutable()
            True
        """
        return not self._is_mutable

    def change_ring(self, R):
        """
        Change the base ring of this vector, by coercing each element of
        this vector into R.
        
        EXAMPLES::
        
            sage: v = vector(QQ['x,y'], [1..5]); v.change_ring(GF(3))
            (1, 2, 0, 1, 2)
        """
        P = self.parent()
        if P.base_ring() is R:
            return self
        return P.change_ring(R)(self)

    def additive_order(self):
        """
        Return the additive order of self.
        
        EXAMPLES::
        
            sage: v = vector(Integers(4), [1,2])
            sage: v.additive_order()
            4
        
        ::
        
            sage: v = vector([1,2,3])
            sage: v.additive_order()
            +Infinity
        
        ::
        
            sage: v = vector(Integers(30), [6, 15]); v
            (6, 15)
            sage: v.additive_order()
            10
            sage: 10*v
            (0, 0)
        """
        v = [None]*self.degree()        
        cdef int i
        for i from 0 <= i < self.degree():
            v[i] = self[i].additive_order()
            if v[i] == +Infinity:
               return +Infinity
        return sage.rings.arith.LCM(v)

    def iteritems(self):
        """
        Return iterator over self.

        EXAMPLES::

            sage: v = vector([1,2/3,pi])
            sage: v.iteritems()
            <dictionary-itemiterator object at ...>
            sage: list(v.iteritems())
            [(0, 1), (1, 2/3), (2, pi)]
        """
        return self.dict(copy=False).iteritems()

    def __abs__(self):
        """
        Return the square root of the sum of the squares of the entries of
        this vector.
        
        EXAMPLES::
        
            sage: v = vector([1..5]); abs(v)
            sqrt(55)
            sage: v = vector(RDF, [1..5]); abs(v)
            7.4161984871
        """
        return sum([x**2 for x in self.list()]).sqrt()

    def norm(self, p=sage.rings.integer.Integer(2)):
        r"""
        Return the `p`-norm of ``self``.

        INPUT:

        - ``p`` - default: 2 - ``p`` can be a real number greater than 1,
          infinity (``oo`` or ``Infinity``), or a symbolic expression.

            - `p=1`: the taxicab (Manhattan) norm
            - `p=2`: the usual Euclidean norm (the default)
            - `p=\infty`: the maximum entry (in absolute value)

        .. note::

            See also :func:`sage.misc.functional.norm`

        EXAMPLES::

            sage: v = vector([1,2,-3])
            sage: v.norm(5)
            276^(1/5)

        The default is the usual Euclidean norm.  ::

            sage: v.norm()
            sqrt(14)
            sage: v.norm(2)
            sqrt(14)

        The infinity norm is the maximum size (in absolute value)
        of the entries.  ::

            sage: v.norm(Infinity)
            3
            sage: v.norm(oo)
            3

        Real or symbolic values may be used for ``p``.  ::

            sage: v=vector(RDF,[1,2,3])
            sage: v.norm(5)
            3.07738488539
            sage: v.norm(pi/2)
            4.2165958647
            sage: _=var('a b c d p'); v=vector([a, b, c, d])
            sage: v.norm(p)
            (abs(a)^p + abs(b)^p + abs(c)^p + abs(d)^p)^(1/p)

        Notice that the result may be a symbolic expression, owing to
        the necessity of taking a square root (in the default case).
        These results can be converted to numerical values if needed. ::

            sage: v = vector(ZZ, [3,4])
            sage: nrm = v.norm(); nrm
            5
            sage: nrm.parent()
            Rational Field

            sage: v = vector(QQ, [3, 5])
            sage: nrm = v.norm(); nrm
            sqrt(34)
            sage: nrm.parent()
            Symbolic Ring
            sage: numeric = N(nrm); numeric
            5.83095189484...
            sage: numeric.parent()
            Real Field with 53 bits of precision

        TESTS:

        The value of ``p`` must be greater than, or
        equal to, one. ::

            sage: v = vector(QQ, [1,2])
            sage: v.norm(0.99)
            Traceback (most recent call last):
            ...
            ValueError: 0.990000 is not greater than or equal to 1

        Norm works with python integers (see :trac:`13502`). ::

            sage: v = vector(QQ, [1,2])
            sage: v.norm(int(2))
            sqrt(5)
        """
        abs_self = [abs(x) for x in self]
        if p == Infinity:
            return max(abs_self)
        try:
            pr = RDF(p)
            if pr < 1:
                raise ValueError("%f is not greater than or equal to 1" %(pr))
        except TypeError:
            pass

        s = sum([a**p for a in abs_self])
        return s**(__one__/p)
    
    cdef int _cmp_c_impl(left, Element right) except -2:
        """
        EXAMPLES::
        
            sage: v = vector(SR, [0,0,0,0])
            sage: v == 0
            True
            sage: v == 1
            False
            sage: v == v
            True
            sage: w = vector(SR, [-1,x,pi,0])
            sage: w < v
            True
            sage: w > v
            False
        """
        cdef Py_ssize_t i
        cdef int c
        for i from 0 <= i < left.degree():
            c = cmp(left[i], right[i])
            if c: return c
        return 0

    # see sage/structure/element.pyx
    def __richcmp__(left, right, int op):
        """
        TESTS::

            sage: F.<y> = PolynomialRing(QQ, 'y')
            sage: type(vector(F, [0]*4, sparse=True))
            <type 'sage.modules.free_module_element.FreeModuleElement_generic_sparse'>
            sage: vector(F, [0,0,0,y]) == vector(F, [0,0,0,y])
            True
            sage: vector(F, [0,0,0,0]) == vector(F, [0,2,0,y])
            False
        """
        return (<Element>left)._richcmp(right, op)

    def __getitem__(self, i):
        """
        Return `i`-th entry or slice of self.

        EXAMPLES::

        This just raises NotImplementedError since this is an abstract
        base class, and __getitem__ has to be overloaded in the
        derived class::

            sage: v = sage.modules.free_module_element.FreeModuleElement(QQ^3)
            sage: v.__getitem__(0)
            Traceback (most recent call last):
            ...
            NotImplementedError
        """
        raise NotImplementedError

    def __invert__(self):
        """
        Invert v, which makes no sense, and is hence is not implemented.

        EXAMPLES::

            sage: vector([1,2/3,pi]).__invert__()
            Traceback (most recent call last):
            ...
            NotImplementedError
        """
        raise NotImplementedError
        
    def __len__(self):
        """
        EXAMPLES::
        
            sage: len(sage.modules.free_module_element.FreeModuleElement(QQ^2010))
            2010
        """
        return self.parent().degree()
        
    def __mod__(self, p):
        """
        EXAMPLES::
        
            sage: V = vector(ZZ, [5, 9, 13, 15])
            sage: V % 7
            (5, 2, 6, 1)
            sage: parent(V % 7)
            Ambient free module of rank 4 over the principal ideal domain Integer Ring
        """
        return self.parent()([x % p for x in self.list()], copy=False, coerce=False, check=False)

    def Mod(self, p):
        """
        EXAMPLES::
        
            sage: V = vector(ZZ, [5, 9, 13, 15])
            sage: V.Mod(7)
            (5, 2, 6, 1)
            sage: parent(V.Mod(7))
            Vector space of dimension 4 over Ring of integers modulo 7
        """
        return self.change_ring(self.base_ring().quotient_ring(p))

    def list(self, copy=True):
        """
        Return list of elements of self.
        
        INPUT:

            - copy -- bool, whether returned list is a copy that is
              safe to change, is ignored.
            
        EXAMPLES::

            sage: P.<x,y,z> = QQ[]
            sage: v = vector([x,y,z], sparse=True)
            sage: type(v)
            <type 'sage.modules.free_module_element.FreeModuleElement_generic_sparse'>
            sage: a = v.list(); a
            [x, y, z]
            sage: a[0] = x*y; v
            (x, y, z)

        The optional argument ``copy`` is ignored::

            sage: a = v.list(copy=False); a
            [x, y, z]
            sage: a[0] = x*y; v
            (x, y, z)
        """
        cdef Py_ssize_t i
        return [self[i] for i in range(self.degree())]

    def list_from_positions(self, positions):
        """
        Return list of elements chosen from this vector using the
        given positions of this vector.

        INPUT:

            - positions -- iterable of ints
            

        EXAMPLES::

            sage: v = vector([1,2/3,pi])
            sage: v.list_from_positions([0,0,0,2,1])
            [1, 1, 1, pi, 2/3]
        """
        cdef Py_ssize_t i
        return [self[i] for i in positions]

    def lift(self):
        """
        EXAMPLES::
        
            sage: V = vector(Integers(7), [5, 9, 13, 15]) ; V
            (5, 2, 6, 1)
            sage: V.lift()
            (5, 2, 6, 1)
            sage: parent(V.lift())
            Ambient free module of rank 4 over the principal ideal domain Integer Ring
        """
        return self.change_ring(self.base_ring().cover_ring())
        
    def __pos__(self):
        """
        Always returns self, since +self == self.

        EXAMPLES::

            sage: v = vector([1,2/3,8])
            sage: v.__pos__()
            (1, 2/3, 8)
            sage: +v
            (1, 2/3, 8)
        """
        return self
        
    def __pow__(self, n, dummy):
        """
        Raises a NotImplementedError, since powering doesn't make
        sense for vectors.

        EXAMPLES::

            sage: v = vector([1,2/3,8])
            sage: v^2
            Traceback (most recent call last):
            ...
            NotImplementedError
        """
        raise NotImplementedError
        
    def _repr_(self):
        """
        String representation of a vector.
        
        EXAMPLES::
        
            sage: vector(QQ, [])._repr_()
            '()'
            sage: vector(QQ, range(5))._repr_()
            '(0, 1, 2, 3, 4)'
        
        Symbolic are not displayed using ASCII art.
        
        ::
        
            sage: x = var('x')
            sage: v = vector([x/(2*x)+sqrt(2)+var('theta')^3,x/(2*x)]); v
            (sqrt(2) + theta^3 + 1/2, 1/2)
            sage: v._repr_()
            '(sqrt(2) + theta^3 + 1/2, 1/2)'
        """
        d = self.degree()
        if d == 0: return "()"
        # compute column widths
        S = [repr(x) for x in self.list(copy=False)]
        #width = max([len(x) for x in S])
        s = "("
        for i in xrange(d):
            if i == d-1:
                sep = ""
            else:
                sep=", "
            entry = S[i]
            #if i > 0:
            #    entry = " "*(width-len(entry)) + entry
            s = s + entry + sep
        s = s + ")"
        return s
    
    def _maple_init_(self):
        """
        EXAMPLES::
        
            sage: v = vector(ZZ, 4, range(4))               #optional
            sage: maple(v)                                  #optional
            Vector[row](4, [0,1,2,3])
        
        ::
        
            sage: v = vector(QQ, 3, [2/3, 0, 5/4])          #optional
            sage: maple(v)                                  #optional
            Vector[row](3, [2/3,0,5/4])
        
        ::
        
            sage: P.<x> = ZZ[]                                       #optional
            sage: v = vector(P, 3, [x^2 + 2, 2*x + 1, -2*x^2 + 4*x]) #optional
            sage: maple(v)                                           #optional
            Vector[row](3, [x^2+2,2*x+1,-2*x^2+4*x])
        """
        return "Vector[row](%s)"%(str(self.list()))

    def __setitem__(self, i, x):
        """
        Set the `i`-th entry or slice of self to x. This is not implemented,
        since self is an abstract base class.

        EXAMPLES::

            sage: v = sage.modules.free_module_element.FreeModuleElement(QQ^3)
            sage: v[0] = 5
            Traceback (most recent call last):
            ...
            NotImplementedError

        For derived classes, this works::

            sage: v = vector([1,2/3,8])
            sage: v[0] = 5
            sage: v
            (5, 2/3, 8)
        """
        raise NotImplementedError

    def __richcmp__(left, right, int op):
        """
        EXAMPLES::

            sage: v = vector([1,2/3,8])   # indirect test
            sage: v == v 
            True
        """
        cdef int ld, rd
        if not isinstance(left, FreeModuleElement) or not isinstance(right, FreeModuleElement):
            # use the generic compare
            return (<Element>left)._richcmp(right, op)
        ld = (<FreeModuleElement>left)._degree
        rd = (<FreeModuleElement>right)._degree
        if ld < rd:
            return (<Element>left)._rich_to_bool(op, -1)
        elif ld > rd:
            return (<Element>left)._rich_to_bool(op, 1)
        if (<FreeModuleElement>left)._parent.base_ring() is (<FreeModuleElement>right)._parent.base_ring():
            return (<Element>left)._rich_to_bool(op, (
                    <FreeModuleElement>left)._cmp_same_ambient_c(right))
        return (<Element>left)._richcmp(right, op)


    cdef int _cmp_same_ambient_c(left, FreeModuleElement right) except -2:
        return cmp(left.list(copy=False), right.list(copy=False))
    
    def degree(self):
        """
        Return the degree of this vector, which is simply the number
        of entries.

        EXAMPLES::
        
            sage: sage.modules.free_module_element.FreeModuleElement(QQ^389).degree()
            389
            sage: vector([1,2/3,8]).degree()
            3
        """
        return self._degree

    def denominator(self):
        """
        Return the least common multiple of the denominators of the
        entries of self.

        EXAMPLES::

            sage: v = vector([1/2,2/5,3/14])
            sage: v.denominator()
            70
            sage: 2*5*7
            70

        TESTS:

        The following was fixed in trac ticket #8800::

            sage: M = GF(5)^3
            sage: v = M((4,0,2))
            sage: v.denominator()
            1

        """
        R = self.base_ring()
        if self.degree() == 0: return 1
        x = self.list()
        # it may be that the marks do not have a denominator!
        d = x[0].denominator() if hasattr(x[0],'denominator') else 1
        for y in x:
            d = d.lcm(y.denominator()) if hasattr(y,'denominator') else d
        return d

    def dict(self, copy=True):
        """
        Return dictionary of nonzero entries of self.

        INPUT:

            - ``copy`` -- bool (default: True)

        OUTPUT:

            - Python dictionary

        EXAMPLES::

            sage: v = vector([0,0,0,0,1/2,0,3/14])
            sage: v.dict()
            {4: 1/2, 6: 3/14}

        In some cases when copy=False, we get back a dangerous reference::

            sage: v = vector({0:5, 2:3/7}, sparse=True)
            sage: v.dict(copy=False)
            {0: 5, 2: 3/7}
            sage: v.dict(copy=False)[0] = 18
            sage: v
            (18, 0, 3/7)
        """
        e = {}
        for i in xrange(self.degree()):
            c = self[i]
            if c:
                e[i] = c
        return e

    #############################
    # Plotting
    #############################
    def plot(self, plot_type=None, start=None, **kwds):
        """
        INPUT:
        
        - ``plot_type`` - (default: 'arrow' if v has 3 or fewer components,
            otherwise 'step') type of plot. Options are:

            - 'arrow' to draw an arrow

            - 'point' to draw a point at the coordinates specified by the
              vector

            - 'step' to draw a step function representing the coordinates
              of the vector.

          Both 'arrow' and 'point' raise exceptions if the vector has
          more than 3 dimensions.
        
        - ``start`` - (default: origin in correct dimension) may be a tuple,
          list, or vector.

        EXAMPLES:

        The following both plot the given vector::

            sage: v = vector(RDF, (1,2))
            sage: A = plot(v)
            sage: B = v.plot()
            sage: A+B # should just show one vector

        Examples of the plot types::

            sage: A = plot(v, plot_type='arrow')
            sage: B = plot(v, plot_type='point', color='green', size=20)
            sage: C = plot(v, plot_type='step') # calls v.plot_step()
            sage: A+B+C

        You can use the optional arguments for :meth:`plot_step`::

            sage: eps = 0.1
            sage: plot(v, plot_type='step', eps=eps, xmax=5, hue=0)

        Three-dimensional examples::

            sage: v = vector(RDF, (1,2,1))
            sage: plot(v) # defaults to an arrow plot

        ::

            sage: plot(v, plot_type='arrow')

        ::

            sage: from sage.plot.plot3d.shapes2 import frame3d
            sage: plot(v, plot_type='point')+frame3d((0,0,0), v.list())

        ::

            sage: plot(v, plot_type='step') # calls v.plot_step()

        ::

            sage: plot(v, plot_type='step', eps=eps, xmax=5, hue=0)

        With greater than three coordinates, it defaults to a step plot::

            sage: v = vector(RDF, (1,2,3,4))
            sage: plot(v)

        One dimensional vectors are plotted along the horizontal axis of 
        the coordinate plane::

            sage: plot(vector([1]))
        
        An optional start argument may also be specified by a tuple, list, or vector::
        
            sage: u = vector([1,2]); v = vector([2,5])
            sage: plot(u, start=v)

        TESTS::

            sage: u = vector([1,1]); v = vector([2,2,2]); z=(3,3,3)
            sage: plot(u) #test when start=None

        ::

            sage: plot(u, start=v) #test when coordinate dimension mismatch exists
            Traceback (most recent call last):
            ...
            ValueError: vector coordinates are not of the same dimension
            sage: P = plot(v, start=z) #test when start coordinates are passed as a tuple
            sage: P = plot(v, start=list(z)) #test when start coordinates are passed as a list
        """
        # Give sensible defaults based on the vector length
        if plot_type is None:
            if len(self)<=3:
                plot_type='arrow'
            else:
                plot_type='step'

        coords = self.list()

        if start is None:
            start = [0]*len(coords)
        elif len(start)!=len(coords):
            raise ValueError("vector coordinates are not of the same dimension")
        else:
            start = list(start)


        if plot_type == 'arrow' or plot_type == 'point':
            dimension = len(coords)
            if dimension == 3:
                from sage.plot.plot3d.shapes2 import line3d, point3d
                
                if plot_type == 'arrow':
                    return line3d([start, [(u+v) for u,v in zip(coords, start)]], arrow_head=True, **kwds)
                else:
                    return point3d(coords, **kwds)
            elif dimension < 3:
                if dimension < 2:
                    # pad to make 2-dimensional
                    coords.extend([0]*(2-dimension))
                    start.extend([0]*(2-dimension))

                from sage.plot.all import arrow, point
                if plot_type == 'arrow':
                    return arrow(start, [(u+v) for u,v in zip(coords, start)], **kwds)
                else:
                    return point(coords, **kwds)
            else:
                raise ValueError("arrow and point plots require vectors with 3 or fewer components")

        elif plot_type == 'step':
            return self.plot_step(**kwds)
        else:
            raise NotImplementedError("plot_type was unrecognized")

    def plot_step(self, xmin=0, xmax=1, eps=None, res=None,
             connect=True, **kwds):
        """
        INPUT:
        
        -  ``xmin`` - (default: 0) start x position to start
           plotting
        
        -  ``xmax`` - (default: 1) stop x position to stop
           plotting
        
        -  ``eps`` - (default: determined by xmax) we view this
           vector as defining a function at the points xmin, xmin + eps, xmin
           + 2\*eps, ...,
        
        -  ``res`` - (default: all points) total number of
           points to include in the graph
        
        -  ``connect`` - (default: True) if True draws a line;
           otherwise draw a list of points.
        
        
        EXAMPLES::
        
            sage: eps=0.1
            sage: v = vector(RDF, [sin(n*eps) for n in range(100)])
            sage: v.plot_step(eps=eps, xmax=5, hue=0)
        """
        if res is None:
            res = self.degree()
        if eps is None:
            eps = float(xmax - xmin)/res
        v = []
        x = xmin
        for i in range(0, self.degree(), int(math.ceil(self.degree()/res))):
            y = float(self[i])
            if x > xmax:
                break
            v.append((x,y))
            x += eps
            v.append((x,y))
        from sage.plot.all import line, points
        if connect:
            return line(v, **kwds)
        else:
            return points(v, **kwds)

    def dot_product(self, right):
        r"""
        Return the dot product of ``self`` and ``right``, which is the sum of the
        product of the corresponding entries.

        INPUT:

        - ``right`` - a vector of the same degree as ``self``.
          It does not need to belong to the same parent as ``self``,
          so long as the necessary products and sums are defined.

        OUTPUT:

        If ``self`` and ``right`` are the vectors `\vec{x}` and `\vec{y}`,
        of degree `n`, then this method returns

        .. math::

            \sum_{i=1}^{n}x_iy_i

        .. note::

            The :meth:`inner_product` is a more general version of
            this method, and the :meth:`hermitian_inner_product`
            method may be more appropriate if your vectors
            have complex entries.

        EXAMPLES::

            sage: V = FreeModule(ZZ, 3)
            sage: v = V([1,2,3])
            sage: w = V([4,5,6])
            sage: v.dot_product(w)
            32

        The vectors may be from different vector spaces,
        provided the necessary operations make sense.
        Notice that coercion will generate a result of
        the same type, even if the order of the
        arguments is reversed.::

            sage: v = vector(ZZ, [1,2,3])
            sage: w = vector(FiniteField(3), [0,1,2])
            sage: ip = w.dot_product(v); ip
            2
            sage: ip.parent()
            Finite Field of size 3

            sage: ip = v.dot_product(w); ip
            2
            sage: ip.parent()
            Finite Field of size 3

        The dot product of a vector with itself is the 2-norm, squared. ::

            sage: v = vector(QQ, [3, 4, 7])
            sage: v.dot_product(v) - v.norm()^2
            0

        TESTS:

        The second argument must be a free module element. ::

            sage: v = vector(QQ, [1,2])
            sage: v.dot_product('junk')
            Traceback (most recent call last):
            ...
            TypeError: right must be a free module element

        The degrees of the arguments must match. ::

            sage: v = vector(QQ, [1,2])
            sage: w = vector(QQ, [1,2,3])
            sage: v.dot_product(w)
            Traceback (most recent call last):
            ...
            ArithmeticError: degrees (2 and 3) must be the same
        """
        if not PY_TYPE_CHECK(right, FreeModuleElement):
            raise TypeError("right must be a free module element")
        r = right.list(copy=False)
        l = self.list(copy=False)
        if len(r) != len(l):
            raise ArithmeticError("degrees (%s and %s) must be the same"%(len(l),len(r)))
        if len(r) == 0:
            return self._parent.base_ring()(0)
        sum = l[0] * r[0]
        cdef Py_ssize_t i
        for i from 1 <= i < len(l):
            sum += l[i] * r[i]
        return sum
        
    def cross_product(self, right):
        """
        Return the cross product of self and right, which is only defined
        for vectors of length 3 or 7.

        INPUT:

        - ``right`` - A vector of the same size as ``self``, either 
          degree three or degree seven.

        OUTPUT:

        The cross product (vector product) of ``self`` and ``right``,
        a vector of the same size of ``self`` and ``right``.
        
        This product is performed under the assumption that the basis
        vectors are orthonormal.
        
        EXAMPLES::
        
            sage: v = vector([1,2,3]); w = vector([0,5,-9])
            sage: v.cross_product(v)
            (0, 0, 0)
            sage: u = v.cross_product(w); u
            (-33, 9, 5)
            sage: u.dot_product(v)
            0
            sage: u.dot_product(w)
            0

        The cross product is defined for degree seven vectors as well.
        [WIKIPEDIA:CROSSPRODUCT]_
        The 3-D cross product is achieved using the quaternians, 
        whereas the 7-D cross product is achieved using the octions. ::

            sage: u = vector(QQ, [1, -1/3, 57, -9, 56/4, -4,1])
            sage: v = vector(QQ, [37, 55, -99/57, 9, -12, 11/3, 4/98])
            sage: u.cross_product(v)
            (1394815/2793, -2808401/2793, 39492/49, -48737/399, -9151880/2793, 62513/2793, -326603/171)

        The degree seven cross product is anticommutative. ::

            sage: u.cross_product(v) + v.cross_product(u)
            (0, 0, 0, 0, 0, 0, 0)

        The degree seven cross product is distributive across addition. ::

            sage: v = vector([-12, -8/9, 42, 89, -37, 60/99, 73])
            sage: u = vector([31, -42/7, 97, 80, 30/55, -32, 64])
            sage: w = vector([-25/4, 40, -89, -91, -72/7, 79, 58])
            sage: v.cross_product(u + w) - (v.cross_product(u) + v.cross_product(w))
            (0, 0, 0, 0, 0, 0, 0)

        The degree seven cross product respects scalar multiplication. ::

            sage: v = vector([2, 17, -11/5, 21, -6, 2/17, 16])
            sage: u = vector([-8, 9, -21, -6, -5/3, 12, 99])
            sage: (5*v).cross_product(u) - 5*(v.cross_product(u))
            (0, 0, 0, 0, 0, 0, 0)
            sage: v.cross_product(5*u) - 5*(v.cross_product(u))
            (0, 0, 0, 0, 0, 0, 0)
            sage: (5*v).cross_product(u) - (v.cross_product(5*u))
            (0, 0, 0, 0, 0, 0, 0)

        The degree seven cross product respects the scalar triple product. ::

            sage: v = vector([2,6,-7/4,-9/12,-7,12,9])
            sage: u = vector([22,-7,-9/11,12,15,15/7,11])
            sage: w = vector([-11,17,19,-12/5,44,21/56,-8])
            sage: v.dot_product(u.cross_product(w)) - w.dot_product(v.cross_product(u))
            0

        TESTS:

        Both vectors need to be of length three or both vectors need to be of length seven. ::

            sage: u = vector(range(7))
            sage: v = vector(range(3))
            sage: u.cross_product(v)
            Traceback (most recent call last):
            ...
            ArithmeticError: Cross product only defined for vectors of length three or seven, not (7 and 3)

        REFERENCES:

        .. [WIKIPEDIA:CROSSPRODUCT] Algebraic Properties of the Cross Product
           http://en.wikipedia.org/wiki/Cross_product
        
        AUTHOR:

        Billy Wonderly (2010-05-11), Added 7-D Cross Product
        """
        if not PY_TYPE_CHECK(right, FreeModuleElement):
            raise TypeError("right must be a free module element")
        r = right.list(copy=False)
        l = self.list(copy=False)
        if len(r) == 3 and len(l) == 3:
            return vector([l[1]*r[2] - l[2]*r[1],
                           l[2]*r[0] - l[0]*r[2],
                           l[0]*r[1] - l[1]*r[0]])

        elif len(r) == 7 and len(l) == 7:
            return vector([l[1]*r[3] - l[3]*r[1] + l[2]*r[6] - l[6]*r[2] + l[4]*r[5] - l[5]*r[4],
                           l[2]*r[4] - l[4]*r[2] + l[3]*r[0] - l[0]*r[3] + l[5]*r[6] - l[6]*r[5],
                           l[3]*r[5] - l[5]*r[3] + l[4]*r[1] - l[1]*r[4] + l[6]*r[0] - l[0]*r[6],
                           l[4]*r[6] - l[6]*r[4] + l[5]*r[2] - l[2]*r[5] + l[0]*r[1] - l[1]*r[0],
                           l[5]*r[0] - l[0]*r[5] + l[6]*r[3] - l[3]*r[6] + l[1]*r[2] - l[2]*r[1],
                           l[6]*r[1] - l[1]*r[6] + l[0]*r[4] - l[4]*r[0] + l[2]*r[3] - l[3]*r[2],
                           l[0]*r[2] - l[2]*r[0] + l[1]*r[5] - l[5]*r[1] + l[3]*r[4] - l[4]*r[3]])

        else:
            raise ArithmeticError("Cross product only defined for vectors of length three or seven, not (%s and %s)"%(len(l),len(r)))

    
        
    def pairwise_product(self, right):
        """
        Return the pairwise product of self and right, which is a vector of
        the products of the corresponding entries.
        
        INPUT:
        
        
        -  ``right`` - vector of the same degree as self. It
           need not be in the same vector space as self, as long as the
           coefficients can be multiplied.
        
        
        EXAMPLES::
        
            sage: V = FreeModule(ZZ, 3)
            sage: v = V([1,2,3])
            sage: w = V([4,5,6])
            sage: v.pairwise_product(w)
            (4, 10, 18)
            sage: sum(v.pairwise_product(w)) == v.dot_product(w)
            True
        
        ::
        
            sage: W = VectorSpace(GF(3),3)
            sage: w = W([0,1,2])
            sage: w.pairwise_product(v)
            (0, 2, 0)
            sage: w.pairwise_product(v).parent()
            Vector space of dimension 3 over Finite Field of size 3
        
        Implicit coercion is well defined (regardless of order), so we
        get 2 even if we do the dot product in the other order.
        
        ::
        
            sage: v.pairwise_product(w).parent()  
            Vector space of dimension 3 over Finite Field of size 3
        
        TESTS::
        
            sage: x, y = var('x, y') 
        
        ::
        
            sage: parent(vector(ZZ,[1,2]).pairwise_product(vector(ZZ,[1,2]))) 
            Ambient free module of rank 2 over the principal ideal domain Integer Ring 
            sage: parent(vector(ZZ,[1,2]).pairwise_product(vector(QQ,[1,2]))) 
            Vector space of dimension 2 over Rational Field 
            sage: parent(vector(QQ,[1,2]).pairwise_product(vector(ZZ,[1,2]))) 
            Vector space of dimension 2 over Rational Field 
            sage: parent(vector(QQ,[1,2]).pairwise_product(vector(QQ,[1,2]))) 
            Vector space of dimension 2 over Rational Field 
        
        ::
        
            sage: parent(vector(QQ,[1,2,3,4]).pairwise_product(vector(ZZ[x],[1,2,3,4]))) 
            Ambient free module of rank 4 over the principal ideal domain Univariate Polynomial Ring in x over Rational Field 
            sage: parent(vector(ZZ[x],[1,2,3,4]).pairwise_product(vector(QQ,[1,2,3,4]))) 
            Ambient free module of rank 4 over the principal ideal domain Univariate Polynomial Ring in x over Rational Field 
        
        ::
        
            sage: parent(vector(QQ,[1,2,3,4]).pairwise_product(vector(ZZ[x][y],[1,2,3,4]))) 
            Ambient free module of rank 4 over the integral domain Univariate Polynomial Ring in y over Univariate Polynomial Ring in x over Rational Field 
            sage: parent(vector(ZZ[x][y],[1,2,3,4]).pairwise_product(vector(QQ,[1,2,3,4]))) 
            Ambient free module of rank 4 over the integral domain Univariate Polynomial Ring in y over Univariate Polynomial Ring in x over Rational Field 
        
        ::
        
            sage: parent(vector(QQ[x],[1,2,3,4]).pairwise_product(vector(ZZ[x][y],[1,2,3,4]))) 
            Ambient free module of rank 4 over the integral domain Univariate Polynomial Ring in y over Univariate Polynomial Ring in x over Rational Field 
            sage: parent(vector(ZZ[x][y],[1,2,3,4]).pairwise_product(vector(QQ[x],[1,2,3,4]))) 
            Ambient free module of rank 4 over the integral domain Univariate Polynomial Ring in y over Univariate Polynomial Ring in x over Rational Field 
        
        ::
        
            sage: parent(vector(QQ[y],[1,2,3,4]).pairwise_product(vector(ZZ[x][y],[1,2,3,4]))) 
            Ambient free module of rank 4 over the integral domain Univariate Polynomial Ring in y over Univariate Polynomial Ring in x over Rational Field 
            sage: parent(vector(ZZ[x][y],[1,2,3,4]).pairwise_product(vector(QQ[y],[1,2,3,4]))) 
            Ambient free module of rank 4 over the integral domain Univariate Polynomial Ring in y over Univariate Polynomial Ring in x over Rational Field 
        
        ::
        
            sage: parent(vector(ZZ[x],[1,2,3,4]).pairwise_product(vector(ZZ[y],[1,2,3,4]))) 
            Traceback (most recent call last): 
            ... 
            TypeError: no common canonical parent for objects with parents: 'Ambient free module of rank 4 over the integral domain Univariate Polynomial Ring in x over Integer Ring' and 'Ambient free module of rank 4 over the integral domain Univariate Polynomial Ring in y over Integer Ring'
            sage: parent(vector(ZZ[x],[1,2,3,4]).pairwise_product(vector(QQ[y],[1,2,3,4]))) 
            Traceback (most recent call last): 
            ... 
            TypeError: no common canonical parent for objects with parents: 'Ambient free module of rank 4 over the integral domain Univariate Polynomial Ring in x over Integer Ring' and 'Ambient free module of rank 4 over the principal ideal domain Univariate Polynomial Ring in y over Rational Field'
            sage: parent(vector(QQ[x],[1,2,3,4]).pairwise_product(vector(ZZ[y],[1,2,3,4]))) 
            Traceback (most recent call last): 
            ... 
            TypeError: no common canonical parent for objects with parents: 'Ambient free module of rank 4 over the principal ideal domain Univariate Polynomial Ring in x over Rational Field' and 'Ambient free module of rank 4 over the integral domain Univariate Polynomial Ring in y over Integer Ring'
            sage: parent(vector(QQ[x],[1,2,3,4]).pairwise_product(vector(QQ[y],[1,2,3,4]))) 
            Traceback (most recent call last): 
            ... 
            TypeError: no common canonical parent for objects with parents: 'Ambient free module of rank 4 over the principal ideal domain Univariate Polynomial Ring in x over Rational Field' and 'Ambient free module of rank 4 over the principal ideal domain Univariate Polynomial Ring in y over Rational Field'
            sage: v = vector({1: 1, 3: 2})  # test sparse vectors
            sage: w = vector({0: 6, 3: -4})
            sage: v.pairwise_product(w)
            (0, 0, 0, -8)
            sage: w.pairwise_product(v) == v.pairwise_product(w)
            True
        """ 
        if not PY_TYPE_CHECK(right, FreeModuleElement):
            raise TypeError("right must be a free module element")
        if self._parent is not (<FreeModuleElement>right)._parent:
            self, right = canonical_coercion(self, right)
        return self._pairwise_product_(right)             

    def element(self):
        """
        Simply returns self.  This is useful, since for many objects,
        self.element() returns a vector corresponding to self.

        EXAMPLES::

            sage: v = vector([1/2,2/5,0]); v
            (1/2, 2/5, 0)
            sage: v.element()
            (1/2, 2/5, 0)
        """
        return self
        
    def get(self, Py_ssize_t i):
        """
        The get method is in some cases more efficient (and more
        dangerous) than __getitem__, because it is not guaranteed to
        do any error checking.

        EXAMPLES::

            sage: vector([1/2,2/5,0]).get(0)
            1/2
            sage: vector([1/2,2/5,0]).get(3)
            Traceback (most recent call last):
            ...
            IndexError: index out of range
        """
        return self[i]
    
    def set(self, Py_ssize_t i, x):
        """
        The set method is meant to be more efficient than __setitem__,
        because it need not be guaranteed to do any error checking or
        coercion. Use with great, great care.

        EXAMPLES::
        
            sage: v = vector([1/2,2/5,0]); v
            (1/2, 2/5, 0)
            sage: v.set(2, -15/17); v
            (1/2, 2/5, -15/17)
        """
        self[i] = x


    def normalize(self):
        """
        Return this vector divided through by the first nonzero entry of
        this vector.
        
        EXAMPLES::
        
            sage: v = vector(QQ,[0,4/3,5,1,2])
            sage: v.normalize()
            (0, 1, 15/4, 3/4, 3/2)
        """
        cdef Py_ssize_t i
        for i from 0 <= i < self._degree:
            if self[i] != 0:
                return (~self[i]) * self
        return self

    def conjugate(self):
        r"""
        Returns a vector where every entry has been replaced by its complex conjugate.

        OUTPUT:

        A vector of the same length, over the same ring,
        but with each entry replaced by the complex conjugate, as
        implemented by the ``conjugate()`` method for elements of
        the base ring, which is presently always complex conjugation.

        EXAMPLES::

            sage: v = vector(CDF, [2.3 - 5.4*I, -1.7 + 3.6*I])
            sage: w = v.conjugate(); w
            (2.3 + 5.4*I, -1.7 - 3.6*I)
            sage: w.parent()
            Vector space of dimension 2 over Complex Double Field

        Even if conjugation seems nonsensical over a certain ring, this
        method for vectors cooperates silently. ::

            sage: u = vector(ZZ, range(6))
            sage: u.conjugate()
            (0, 1, 2, 3, 4, 5)

        Sage implements a few specialized subfields of the complex numbers,
        such as the cyclotomic fields.  This example uses such a field
        containing a primitive 7-th root of unity named ``a``. ::

            sage: F.<a> = CyclotomicField(7)
            sage: v = vector(F, [a^i for i in range(7)])
            sage: v
            (1, a, a^2, a^3, a^4, a^5, -a^5 - a^4 - a^3 - a^2 - a - 1)
            sage: v.conjugate()
            (1, -a^5 - a^4 - a^3 - a^2 - a - 1, a^5, a^4, a^3, a^2, a)

        Sparse vectors are returned as such. ::

            sage: v = vector(CC, {1: 5 - 6*I, 3: -7*I}); v
            (0.000000000000000, 5.00000000000000 - 6.00000000000000*I, 0.000000000000000, -7.00000000000000*I)
            sage: v.is_sparse()
            True
            sage: vc = v.conjugate(); vc
            (0.000000000000000, 5.00000000000000 + 6.00000000000000*I, 0.000000000000000, 7.00000000000000*I)
            sage: vc.conjugate()
            (0.000000000000000, 5.00000000000000 - 6.00000000000000*I, 0.000000000000000, -7.00000000000000*I)

        TESTS::

            sage: n = 15
            sage: x = vector(CDF, [sin(i*pi/n)+cos(i*pi/n)*I for i in range(n)])
            sage: x + x.conjugate() in RDF^n
            True
            sage: I*(x - x.conjugate()) in RDF^n
            True

        The parent of the conjugate is the same as that of the orginal vector.
        We test this by building a specialized vector space with a non-standard
        inner product, and constructing a test vector in this space. ::

            sage: V = VectorSpace(CDF, 2, inner_product_matrix = [[2,1],[1,5]])
            sage: v = vector(CDF, [2-3*I, 4+5*I])
            sage: w = V(v)
            sage: w.parent()
            Ambient quadratic space of dimension 2 over Complex Double Field
            Inner product matrix:
            [2.0 1.0]
            [1.0 5.0]
            sage: w.conjugate().parent()
            Ambient quadratic space of dimension 2 over Complex Double Field
            Inner product matrix:
            [2.0 1.0]
            [1.0 5.0]
        """
        V = self.parent()
        R = self.base_ring()
        degree = self.degree()
        if self.is_sparse():
            # this could be a dictionary comprehension in Python 3
            entries = {}
            for index, entry in self.iteritems():
                entries[index] = entry.conjugate()
        else:
            entries = [entry.conjugate() for entry in self]
        return V(vector(R, degree, entries))

    def inner_product(self, right):
        r"""
        Returns the inner product of ``self`` and ``right``,
        possibly using an inner product matrix from the parent of ``self``.

        INPUT:

        - ``right`` - a vector of the same degree as ``self``

        OUTPUT:

        If the parent vector space does not have an inner product
        matrix defined, then this is the usual dot product
        (:meth:`dot_product`).  If ``self`` and ``right`` are
        considered as single column matrices, `\vec{x}` and `\vec{y}`,
        and `A` is the inner product matrix, then this method computes

        .. math::

            \left(\vec{x}\right)^tA\vec{y}

        where `t` indicates the transpose.

        .. note::

            If your vectors have complex entries, the
            :meth:`hermitian_inner_product` may be more
            appropriate for your purposes.

        EXAMPLES::

            sage: v = vector(QQ, [1,2,3])
            sage: w = vector(QQ, [-1,2,-3])
            sage: v.inner_product(w)
            -6
            sage: v.inner_product(w) == v.dot_product(w)
            True

        The vector space or free module that is the parent to
        ``self`` can have an inner product matrix defined, which
        will be used by this method.  This matrix will be passed
        through to subspaces. ::

            sage: ipm = matrix(ZZ,[[2,0,-1], [0,2,0], [-1,0,6]])
            sage: M = FreeModule(ZZ, 3, inner_product_matrix = ipm)
            sage: v = M([1,0,0])
            sage: v.inner_product(v)
            2
            sage: K = M.span_of_basis([[0/2,-1/2,-1/2], [0,1/2,-1/2],[2,0,0]])
            sage: (K.0).inner_product(K.0)
            2
            sage: w = M([1,3,-1])
            sage: v = M([2,-4,5])
            sage: w.row()*ipm*v.column() == w.inner_product(v)
            True

        Note that the inner product matrix comes from the parent of ``self``.
        So if a vector is not an element of the correct parent, the result
        could be a source of confusion.  ::

            sage: V = VectorSpace(QQ, 2, inner_product_matrix=[[1,2],[2,1]])
            sage: v = V([12, -10])
            sage: w = vector(QQ, [10,12])
            sage: v.inner_product(w)
            88
            sage: w.inner_product(v)
            0
            sage: w = V(w)
            sage: w.inner_product(v)
            88

        .. note::

            The use of an inner product matrix makes no restrictions on
            the nature of the matrix.  In particular, in this context it
            need not be Hermitian and positive-definite (as it is in the
            example above).

        TESTS:

        Most error handling occurs in the :meth:`dot_product` method.
        But with an inner product defined, this method will check
        that the input is a vector or free module element. ::

            sage: W = VectorSpace(RDF, 2, inner_product_matrix = matrix(RDF, 2, [1.0,2.0,3.0,4.0]))
            sage: v = W([2.0, 4.0])
            sage: v.inner_product(5)
            Traceback (most recent call last):
            ...
            TypeError: right must be a free module element
        """
        if self.parent().is_ambient() and self.parent()._inner_product_is_dot_product():
            return self.dot_product(right)
        if not isinstance(right, FreeModuleElement):
            raise TypeError("right must be a free module element")
        M = self.parent()
        if M.is_ambient() or M.uses_ambient_inner_product():
            A = M.ambient_module().inner_product_matrix()
            return A.linear_combination_of_rows(self).dot_product(right)
        else:
            A = M.inner_product_matrix()
            v = M.coordinate_vector(self)
            w = M.coordinate_vector(right)
            return A.linear_combination_of_rows(v).dot_product(w)

    def outer_product(self, right):
        r"""
        Returns a matrix, the outer product of two vectors ``self`` and ``right``.

        INPUT:

        - ``right`` - a vector (or free module element) of any size, whose
          elements are compatible (with regard to multiplication) with the
          elements of ``self``.

        OUTPUT:

        The outer product of two vectors `x` and `y` (respectively
        ``self`` and ``right``) can be described several ways.  If we
        interpret `x` as a `m\times 1` matrix and interpret `y` as a
        `1\times n` matrix, then the outer product is the `m\times n`
        matrix from the usual matrix product `xy`.  Notice how this
        is the "opposite" in some ways from an inner product (which
        would require `m=n`).

        If we just consider vectors, use each entry of `x` to create
        a scalar multiples of the vector `y` and use these vectors as
        the rows of a matrix.  Or use each entry of `y` to create a
        scalar multiples of `x` and use these vectors as the columns
        of a matrix.

        EXAMPLES::

            sage: u = vector(QQ, [1/2, 1/3, 1/4, 1/5])
            sage: v = vector(ZZ, [60, 180, 600])
            sage: u.outer_product(v)
            [ 30  90 300]
            [ 20  60 200]
            [ 15  45 150]
            [ 12  36 120]
            sage: M = v.outer_product(u); M
            [ 30  20  15  12]
            [ 90  60  45  36]
            [300 200 150 120]
            sage: M.parent()
            Full MatrixSpace of 3 by 4 dense matrices over Rational Field

        The more general :meth:`sage.matrix.matrix2.tensor_product` is an
        operation on a pair of matrices.  If we construe a pair of vectors
        as a column vector and a row vector, then an outer product and a
        tensor product are identical.  Thus `tensor_product` is a synonym
        for this method.  ::

            sage: u = vector(QQ, [1/2, 1/3, 1/4, 1/5])
            sage: v = vector(ZZ, [60, 180, 600])
            sage: u.tensor_product(v) == (u.column()).tensor_product(v.row())
            True

        The result is always a dense matrix, no matter if the two
        vectors are, or are not, dense.  ::

            sage: d = vector(ZZ,[4,5], sparse=False)
            sage: s = vector(ZZ, [1,2,3], sparse=True)
            sage: dd = d.outer_product(d)
            sage: ds = d.outer_product(s)
            sage: sd = s.outer_product(d)
            sage: ss = s.outer_product(s)
            sage: all([dd.is_dense(), ds.is_dense(), sd.is_dense(), dd.is_dense()])
            True

        Vectors with no entries do the right thing.  ::

            sage: v = vector(ZZ, [])
            sage: z = v.outer_product(v)
            sage: z.parent()
            Full MatrixSpace of 0 by 0 dense matrices over Integer Ring

        There is a fair amount of latitude in the value of the ``right``
        vector, and the matrix that results can have entries from a new
        ring large enough to contain the result. If you know better,
        you can sometimes bring the result down to a less general ring.  ::

            sage: R.<t> = ZZ[]
            sage: v = vector(R, [12, 24*t])
            sage: w = vector(QQ, [1/2, 1/3, 1/4])
            sage: op = v.outer_product(w)
            sage: op
            [   6    4    3]
            [12*t  8*t  6*t]
            sage: op.base_ring()
            Univariate Polynomial Ring in t over Rational Field
            sage: m = op.change_ring(R); m
            [   6    4    3]
            [12*t  8*t  6*t]
            sage: m.base_ring()
            Univariate Polynomial Ring in t over Integer Ring

        But some inputs are not compatible, even if vectors. ::

            sage: w = vector(GF(5), [1,2])
            sage: v = vector(GF(7), [1,2,3,4])
            sage: z = w.outer_product(v)
            Traceback (most recent call last):
            ...
            TypeError: unsupported operand parent(s) for '*': 'Full MatrixSpace of 2 by 1 dense matrices over Finite Field of size 5' and 'Full MatrixSpace of 1 by 4 dense matrices over Finite Field of size 7'

        And some inputs don't make any sense at all. ::

            sage: w=vector(QQ, [5,10])
            sage: z=w.outer_product(6)
            Traceback (most recent call last):
            ...
            TypeError: right operand in an outer product must be a vector, not an element of Integer Ring
        """
        if not PY_TYPE_CHECK(right, FreeModuleElement):
            raise TypeError('right operand in an outer product must be a vector, not an element of %s' % right.parent())
        return self.column()*right.row()

    # tensor product is an alias in the special case of two vectors
    tensor_product = outer_product

    def hermitian_inner_product(self, right):
        r"""
        Returns the dot product, but with the entries of the first vector
        conjugated beforehand.

        INPUT:

        - ``right`` - a vector of the same degree as ``self``

        OUTPUT:

        If ``self`` and ``right`` are the vectors `\vec{x}` and
        `\vec{y}` of degree `n` then this routine computes

        .. math::

            \sum_{i=1}^{n}\overline{x}_i{y}_i

        where the bar indicates complex conjugation.

        .. note::

            If your vectors do not contain complex entries, then
            :meth:`dot_product` will return the same result without
            the overhead of conjugating elements of ``self``.

            If you are not computing a weighted inner product, and
            your vectors do not have complex entries, then the
            :meth:`dot_product` will return the same result.

        EXAMPLES::

            sage: v = vector(CDF, [2+3*I, 5-4*I])
            sage: w = vector(CDF, [6-4*I, 2+3*I])
            sage: v.hermitian_inner_product(w)
            -2.0 - 3.0*I

        Sage implements a few specialized fields over the complex numbers,
        such as cyclotomic fields and quadratic number fields.  So long as
        the base rings have a conjugate method, then the Hermitian inner
        product will be available. ::

            sage: Q.<a> = QuadraticField(-7)
            sage: a^2
            -7
            sage: v = vector(Q, [3+a, 5-2*a])
            sage: w = vector(Q, [6, 4+3*a])
            sage: v.hermitian_inner_product(w)
            17*a - 4

        The Hermitian inner product should be additive in
        each argument (we only need to test one), linear
        in each argument (with conjugation on the first scalar),
        and anti-commutative. ::

            sage: alpha = CDF(5.0 + 3.0*I)
            sage: u = vector(CDF, [2+4*I, -3+5*I, 2-7*I])
            sage: v = vector(CDF, [-1+3*I, 5+4*I, 9-2*I])
            sage: w = vector(CDF, [8+3*I, -4+7*I, 3-6*I])
            sage: (u+v).hermitian_inner_product(w) == u.hermitian_inner_product(w) + v.hermitian_inner_product(w)
            True
            sage: (alpha*u).hermitian_inner_product(w) == alpha.conjugate()*u.hermitian_inner_product(w)
            True
            sage: u.hermitian_inner_product(alpha*w) == alpha*u.hermitian_inner_product(w)
            True
            sage: u.hermitian_inner_product(v) == v.hermitian_inner_product(u).conjugate()
            True

        For vectors with complex entries, the Hermitian inner product
        has a more natural relationship with the 2-norm (which is the
        default for the :meth:`norm` method). The norm squared equals
        the Hermitian inner product of the vector with itself.  ::

            sage: v = vector(CDF, [-0.66+0.47*I, -0.60+0.91*I, -0.62-0.87*I, 0.53+0.32*I])
            sage: abs(v.norm()^2 - v.hermitian_inner_product(v)) < 1.0e-10
            True

        TESTS:

        This method is built on the :meth:`dot_product` method,
        which allows for a wide variety of inputs.  Any error
        handling happens there. ::

            sage: v = vector(CDF, [2+3*I])
            sage: w = vector(CDF, [5+2*I, 3+9*I])
            sage: v.hermitian_inner_product(w)
            Traceback (most recent call last):
            ...
            ArithmeticError: degrees (1 and 2) must be the same
        """
        return (self.conjugate()).dot_product(right)

    def is_dense(self):
        """
        Return True if this is a dense vector, which is just a
        statement about the data structure, not the number of nonzero
        entries.

        EXAMPLES::

            sage: vector([1/2,2/5,0]).is_dense()
            True
            sage: vector([1/2,2/5,0],sparse=True).is_dense()
            False
        """
        return self.is_dense_c()

    cdef bint is_dense_c(self):
        return self.parent().is_dense()
       
    def is_sparse(self):
        """
        Return True if this is a sparse vector, which is just a
        statement about the data structure, not the number of nonzero
        entries.

        EXAMPLES::

            sage: vector([1/2,2/5,0]).is_sparse()
            False
            sage: vector([1/2,2/5,0],sparse=True).is_sparse()
            True
        """
        return self.is_sparse_c()
        
    cdef bint is_sparse_c(self):
        return self.parent().is_sparse()
    
    def is_vector(self):
        """
        Return True, since this is a vector.

        EXAMPLES::

            sage: vector([1/2,2/5,0]).is_vector()
            True
        """
        return True

    def _mathematica_init_(self):
        """
        Returns string representation of this vector as a Mathematica
        list.
        
        EXAMPLES::
        
            sage: vector((1,2,3), QQ)._mathematica_init_()
            '{1/1, 2/1, 3/1}'
            sage: mathematica(vector((1,2,3), QQ))  #optional -- requires mathematica
            {1, 2, 3}
            sage: a = vector(SR, 5, [1, x, x^2, sin(x), pi]); a
            (1, x, x^2, sin(x), pi)
            sage: a._mathematica_init_()
            '{1, x, (x)^(2), Sin[x], Pi}'
        """
        return '{' + ', '.join([x._mathematica_init_() for x in self.list()]) + '}'

##     def zero_out_positions(self, P):
##         """
##         Set the positions of self in the list P equal to 0.
##         """
##         z = self.base_ring()(0)
##         d = self.degree()
##         for n in P:
##             self[n] = z
        
    def nonzero_positions(self):
        """
        Return the sorted list of integers ``i`` such that ``self[i] != 0``.

        EXAMPLES::

            sage: vector([-1,0,3,0,0,0,0.01]).nonzero_positions()
            [0, 2, 6]
        """
        z = self.base_ring()(0)
        v = self.list()
        cdef Py_ssize_t i
        return [i for i from 0 <= i < self.degree() if v[i] != z]

    def support(self):   # do not override.
        """
        Return the integers ``i`` such that ``self[i] != 0``.
        This is the same as the ``nonzero_positions`` function.

        EXAMPLES::

            sage: vector([-1,0,3,0,0,0,0.01]).support()
            [0, 2, 6]        
        """
        return self.nonzero_positions()

    cpdef int hamming_weight(self):
        """
        Return the number of positions ``i`` such that ``self[i] != 0``.

        EXAMPLES::

            sage: vector([-1,0,3,0,0,0,0.01]).hamming_weight()
            3
        """
        cdef int res=0
        for x in iter(self.list()):
            if not x.is_zero():
                res += 1
        return res

    def _latex_(self):
        r"""
        Return a latex representation of the vector ``self``.

        OUTPUT:

        If self is the free module element (1,2,3,4),
        then a string with the following latex is returned:
        "\left(1,\,2,\,3,\,4\right)" (without the quotes).
        The vector is enclosed in parentheses by default,
        but the delimiters can be changed using the command
        ``latex.vector_delimiters(...)`` as in the example below.

        EXAMPLES::

            sage: v = vector(QQ, [1,2,3])
            sage: latex(v)
            \left(1,\,2,\,3\right)

        This is an example of how to change the delimiters.
        You have the power to mix and match, though it is
        probably not advisable.  For more detail see
        :meth:`~sage.misc.latex.Latex.vector_delimiters`.

            sage: latex.vector_delimiters('[', '\\rangle')
            sage: w = vector(CDF, [1,2,3])
            sage: latex(w)
            \left[1.0,\,2.0,\,3.0\right\rangle
        """
        latex = sage.misc.latex.latex
        vector_delimiters = latex.vector_delimiters()
        s = '\\left' + vector_delimiters[0]
        s += ',\,'.join([latex(a) for a in self.list()])
        return s + '\\right' + vector_delimiters[1]

    def dense_vector(self):
        """
        Return dense version of self.  If self is dense, just return
        self; otherwise, create and return correspond dense vector.

        EXAMPLES::

            sage: vector([-1,0,3,0,0,0]).dense_vector().is_dense()
            True
            sage: vector([-1,0,3,0,0,0],sparse=True).dense_vector().is_dense()
            True
            sage: vector([-1,0,3,0,0,0],sparse=True).dense_vector()
            (-1, 0, 3, 0, 0, 0)
        """
        if self.is_dense():
            return self
        else:
            return self.parent().ambient_module().dense_module()(self.list())

    def sparse_vector(self):
        """
        Return sparse version of self.  If self is sparse, just return
        self; otherwise, create and return correspond sparse vector.

        EXAMPLES::

            sage: vector([-1,0,3,0,0,0]).sparse_vector().is_sparse()
            True
            sage: vector([-1,0,3,0,0,0]).sparse_vector().is_sparse()
            True
            sage: vector([-1,0,3,0,0,0]).sparse_vector()
            (-1, 0, 3, 0, 0, 0)
        """
        if self.is_sparse():
            return self
        else:
            return self.parent().ambient_module().sparse_module()(self.list())
        

    def apply_map(self, phi, R=None, sparse=None):
        """
        Apply the given map phi (an arbitrary Python function or callable
        object) to this free module element. If R is not given,
        automatically determine the base ring of the resulting element.
        
        INPUT:
            sparse -- True or False will control whether the result
              is sparse.  By default, the result is sparse iff self
              is sparse.
        
        
        -  ``phi`` - arbitrary Python function or callable
           object
        
        -  ``R`` - (optional) ring
        
        
        OUTPUT: a free module element over R
        
        EXAMPLES::
        
            sage: m = vector([1,x,sin(x+1)])
            sage: m.apply_map(lambda x: x^2)
            (1, x^2, sin(x + 1)^2)
            sage: m.apply_map(sin)
            (sin(1), sin(x), sin(sin(x + 1)))
        
        ::
        
            sage: m = vector(ZZ, 9, range(9)) 
            sage: k.<a> = GF(9) 
            sage: m.apply_map(k)
            (0, 1, 2, 0, 1, 2, 0, 1, 2)
        
        In this example, we explicitly specify the codomain.
        
        ::
        
            sage: s = GF(3)
            sage: f = lambda x: s(x)
            sage: n = m.apply_map(f, k); n
            (0, 1, 2, 0, 1, 2, 0, 1, 2)
            sage: n.parent()
            Vector space of dimension 9 over Finite Field in a of size 3^2
        
        If your map sends 0 to a non-zero value, then your resulting
        vector is not mathematically sparse::

            sage: v = vector([0] * 6 + [1], sparse=True); v
            (0, 0, 0, 0, 0, 0, 1)
            sage: v2 = v.apply_map(lambda x: x+1); v2
            (1, 1, 1, 1, 1, 1, 2)

        but it's still represented with a sparse data type::

            sage: parent(v2)
            Ambient sparse free module of rank 7 over the principal ideal domain Integer Ring

        This data type is inefficient for dense vectors, so you may
        want to specify sparse=False::

            sage: v2 = v.apply_map(lambda x: x+1, sparse=False); v2
            (1, 1, 1, 1, 1, 1, 2)
            sage: parent(v2)
            Ambient free module of rank 7 over the principal ideal domain Integer Ring

        Or if you have a map that will result in mostly zeroes, you may
        want to specify sparse=True::

            sage: v = vector(srange(10))
            sage: v2 = v.apply_map(lambda x: 0 if x else 1, sparse=True); v2
            (1, 0, 0, 0, 0, 0, 0, 0, 0, 0)
            sage: parent(v2)
            Ambient sparse free module of rank 10 over the principal ideal domain Integer Ring

        TESTS::
        
            sage: m = vector(SR,[])
            sage: m.apply_map(lambda x: x*x) == m
            True

        Check that we don't unnecessarily apply phi to 0 in the sparse case::
        
            sage: m = vector(ZZ, range(1, 4), sparse=True)
            sage: m.apply_map(lambda x: 1/x)
            (1, 1/2, 1/3)

            sage: parent(vector(RDF, (), sparse=True).apply_map(lambda x: x, sparse=True))
            Sparse vector space of dimension 0 over Real Double Field
            sage: parent(vector(RDF, (), sparse=True).apply_map(lambda x: x, sparse=False))
            Vector space of dimension 0 over Real Double Field
            sage: parent(vector(RDF, (), sparse=False).apply_map(lambda x: x, sparse=True))
            Sparse vector space of dimension 0 over Real Double Field
            sage: parent(vector(RDF, (), sparse=False).apply_map(lambda x: x, sparse=False))
            Vector space of dimension 0 over Real Double Field
        """
        if sparse is None:
            sparse = self.is_sparse()

        if self._degree == 0:
            if sparse == self.is_sparse():
                from copy import copy
                return copy(self)
            elif sparse:
                return self.sparse_vector()
            else:
                return self.dense_vector()

        v = None

        if self.is_sparse():
            if len(self.dict(copy=False)) < self._degree:
                # OK, we have some zero entries.
                zero_res = phi(self.base_ring()(0))
                if not zero_res.is_zero():
                    # And phi maps 0 to a non-zero value.
                    v = [zero_res] * self._degree
                    for i,z in self.dict(copy=False).items():
                        v[i] = phi(z)

            if v is None:
                # phi maps 0 to 0 (or else we don't have any zeroes at all)
                v = dict([(i,phi(z)) for i,z in self.dict(copy=False).items()])
        else:
            v = [phi(z) for z in self.list()]
            
        if R is None:
            return vector(v, sparse=sparse)
        else:
            return vector(R, v, sparse=sparse)


    def _derivative(self, var=None):
        """
        Differentiate with respect to var by differentiating each element
        with respect to var.
        
        .. seealso:

           :meth:`derivative`
        
        EXAMPLES::
        
            sage: v = vector([1,x,x^2])
            sage: v._derivative(x)
            (0, 1, 2*x)
            sage: type(v._derivative(x)) == type(v)
            True
            sage: v = vector([1,x,x^2], sparse=True)
            sage: v._derivative(x)
            (0, 1, 2*x)
            sage: type(v._derivative(x)) == type(v)
            True

        If no variables are specified and the vector contains callable
        symbolic expressions, then calculate the matrix derivative
        (i.e., the Jacobian matrix)::
        
            sage: T(r,theta)=[r*cos(theta),r*sin(theta)]
            sage: T
            (r, theta) |--> (r*cos(theta), r*sin(theta))
            sage: T.diff() # matrix derivative
            [   (r, theta) |--> cos(theta) (r, theta) |--> -r*sin(theta)]
            [   (r, theta) |--> sin(theta)  (r, theta) |--> r*cos(theta)]
            sage: diff(T) # matrix derivative again
            [   (r, theta) |--> cos(theta) (r, theta) |--> -r*sin(theta)]
            [   (r, theta) |--> sin(theta)  (r, theta) |--> r*cos(theta)]
            sage: T.diff().det() # Jacobian 
            (r, theta) |--> r*sin(theta)^2 + r*cos(theta)^2
        """
        if var is None: 
            if sage.symbolic.callable.is_CallableSymbolicExpressionRing(self.base_ring()):
                return sage.calculus.all.jacobian(self, self.base_ring().arguments())
            else:
                raise ValueError("No differentiation variable specified.")

        # We would just use apply_map, except that Cython doesn't
        # allow lambda functions
        if self._degree == 0:
            from copy import copy
            return copy(self)

        if self.is_sparse():
            v = dict([(i,z.derivative(var)) for i,z in self.dict().items()])
        else:
            v = [z.derivative(var) for z in self.list()]
            
        return self.parent().ambient_module()(v)

    def derivative(self, *args):
        """
        Derivative with respect to variables supplied in args.
        
        Multiple variables and iteration counts may be supplied; see
        documentation for the global derivative() function for more
        details.

        :meth:`diff` is an alias of this function.
        
        EXAMPLES::
        
            sage: v = vector([1,x,x^2])
            sage: v.derivative(x)
            (0, 1, 2*x)
            sage: type(v.derivative(x)) == type(v)
            True
            sage: v = vector([1,x,x^2], sparse=True)
            sage: v.derivative(x)
            (0, 1, 2*x)
            sage: type(v.derivative(x)) == type(v)
            True
            sage: v.derivative(x,x)
            (0, 0, 2)
        """
        return multi_derivative(self, args)

    diff = derivative

    def integral(self, *args, **kwds):
        """
        Returns a symbolic integral of the vector, component-wise.

        :meth:`integrate` is an alias of the function.

        EXAMPLES::

            sage: t=var('t')                      
            sage: r=vector([t,t^2,sin(t)])
            sage: r.integral(t)
            (1/2*t^2, 1/3*t^3, -cos(t))
            sage: integrate(r,t)
            (1/2*t^2, 1/3*t^3, -cos(t))
            sage: r.integrate(t,0,1)
            (1/2, 1/3, -cos(1) + 1)
            
        """
        from sage.misc.functional import integral
        
        # If Cython supported lambda functions, we would just do
        # return self.apply_map(lambda x: integral(x,*args, **kwds) for x in self)

        if self.is_sparse():
            v = dict([(i,integral(z,*args,**kwds)) for i,z in self.dict(copy=False).items()])
        else:
            v = [integral(z,*args,**kwds) for z in self.list()]
            
        return vector(v,sparse=self.is_sparse())

    integrate=integral


    def nintegral(self, *args, **kwds):
        """
        Returns a numeric integral of the vector, component-wise, and
        the result of the nintegral command on each component of the
        input.

        :meth:`nintegrate` is an alias of the function.

        EXAMPLES::

            sage: t=var('t')                      
            sage: r=vector([t,t^2,sin(t)])
            sage: vec,answers=r.nintegral(t,0,1)
            sage: vec
            (0.5, 0.333333333333, 0.459697694132)
            sage: type(vec)
            <type 'sage.modules.vector_real_double_dense.Vector_real_double_dense'>
            sage: answers
            [(0.5, 5.551115123125784e-15, 21, 0), (0.3333333333333..., 3.70074341541719e-15, 21, 0), (0.45969769413186..., 5.103669643922841e-15, 21, 0)]

            sage: r=vector([t,0,1], sparse=True)
            sage: r.nintegral(t,0,1)            
            ((0.5, 0.0, 1.0), {0: (0.5, 5.551115123125784e-15, 21, 0), 2: (1.0, 1.11022302462515...e-14, 21, 0)})

        """
        # If Cython supported lambda functions, we would just do
        # return self.apply_map(lambda x: x.nintegral(*args, **kwds) for x in self)

        if self.is_sparse():
            v = [(i,z.nintegral(*args,**kwds)) for i,z in self.dict(copy=False).items()]
            answers = dict([(i,a[0]) for i,a in v])
            v=dict(v)
        else:
            v = [z.nintegral(*args,**kwds) for z in self.list()]
            answers = [a[0] for a in v]

        return (vector(answers,sparse=self.is_sparse()), v)

    nintegrate=nintegral

#############################################
# Generic dense element
#############################################
def make_FreeModuleElement_generic_dense(parent, entries, degree):
    """
    EXAMPLES::
    
        sage: sage.modules.free_module_element.make_FreeModuleElement_generic_dense(QQ^3, [1,2,-3/7], 3)
        (1, 2, -3/7)
    """
    # If you think you want to change this function, don't.
    # Instead make a new version with a name like
    #    make_FreeModuleElement_generic_dense_v1
    # and changed the reduce method below.
    cdef FreeModuleElement_generic_dense v
    v = FreeModuleElement_generic_dense.__new__(FreeModuleElement_generic_dense)
    v._entries = entries
    v._parent = parent
    v._degree = degree
    return v

def make_FreeModuleElement_generic_dense_v1(parent, entries, degree, is_mutable):
    """
    EXAMPLES::
    
        sage: v = sage.modules.free_module_element.make_FreeModuleElement_generic_dense_v1(QQ^3, [1,2,-3/7], 3, True); v
        (1, 2, -3/7)
        sage: v[0] = 10; v
        (10, 2, -3/7)
        sage: v = sage.modules.free_module_element.make_FreeModuleElement_generic_dense_v1(QQ^3, [1,2,-3/7], 3, False); v
        (1, 2, -3/7)
        sage: v[0] = 10
        Traceback (most recent call last):
        ...
        ValueError: vector is immutable; please change a copy instead (use copy())
    """
    # If you think you want to change this function, don't.
    # Instead make a new version with a name like
    #    make_FreeModuleElement_generic_dense_v2
    # and changed the reduce method below.
    cdef FreeModuleElement_generic_dense v
    v = FreeModuleElement_generic_dense.__new__(FreeModuleElement_generic_dense)
    v._entries = entries
    v._parent = parent
    v._degree = degree
    v._is_mutable = is_mutable
    return v

cdef class FreeModuleElement_generic_dense(FreeModuleElement):
    """
    A generic dense element of a free module.
    """
    ## these work fine on the command line but fail in doctests :-(
##         TESTS:
##             sage: V = ZZ^3
##             sage: loads(dumps(V)) == V
##             True
##             sage: v = V.0
##             sage: loads(dumps(v)) == v
##             True
##             sage: v = (QQ['x']^3).0
##             sage: loads(dumps(v)) == v
##             True        
    cdef _new_c(self, object v):
        # Create a new dense free module element with minimal overhead and
        # no type checking.
        cdef FreeModuleElement_generic_dense x
        x = <FreeModuleElement_generic_dense>PY_NEW(<object>PY_TYPE(self))
        x._is_mutable = 1
        x._parent = self._parent
        x._entries = v
        x._degree = self._degree
        return x

    cdef bint is_dense_c(self):
        return 1
       
    cdef bint is_sparse_c(self):
        return 0

    def _hash(self):
        """
        Return hash of an immutable form of self (works even if self
        is mutable).

            sage: v = vector([-1,0,3,pi])
            sage: type(v)
            <class 'sage.modules.vector_symbolic_dense.Vector_symbolic_dense'>
            sage: v._hash()   # random output
        """
        return hash(tuple(list(self)))

    def __copy__(self):
        """
        Return a copy of this generic dense vector.

        EXAMPLES::
        
            sage: v = vector([-1,0,3,pi])
            sage: type(v)
            <class 'sage.modules.vector_symbolic_dense.Vector_symbolic_dense'>
            sage: v.__copy__()
            (-1, 0, 3, pi)
            sage: v.__copy__() is v
            False

            sage: copy(v)
            (-1, 0, 3, pi)
            sage: copy(v) == v
            True
            sage: copy(v) is v
            False
        """
        return self._new_c(list(self._entries))

    def __init__(self, parent, entries, coerce=True, copy=True):
        """
        EXAMPLES::

            sage: type(vector([-1,0,3,pi]))   # indirect doctest
            <class 'sage.modules.vector_symbolic_dense.Vector_symbolic_dense'>

        TESTS:
 
        Check that #11751 is fixed::

            sage: K.<x> = QQ[]
            sage: M = K^1
            sage: N = M.span([[1/x]]); N
            Free module of degree 1 and rank 1 over Univariate Polynomial Ring in x over Rational Field
            Echelon basis matrix:
            [1/x]
            sage: N([1/x]) # this used to fail prior to #11751
            (1/x)
            sage: N([1/x^2])
            Traceback (most recent call last):
            ...
            TypeError: element (= [1/x^2]) is not in free module

        ::

            sage: L=K^2
            sage: R=L.span([[x,0],[0,1/x]], check=False, already_echelonized=True)
            sage: R.basis()[0][0].parent()
            Fraction Field of Univariate Polynomial Ring in x over Rational Field
            sage: R=L.span([[x,x^2]])
            sage: R.basis()[0][0].parent()
            Univariate Polynomial Ring in x over Rational Field
        """
        FreeModuleElement.__init__(self, parent)
        R = self.parent().base_ring()
        if entries == 0:
            entries = [R(0)]*self.degree()
        else:
            if not isinstance(entries, (list, tuple)):
                raise TypeError("entries (=%s) must be a list"%(entries, ))
            
            if len(entries) != self.degree():
                raise TypeError("entries must be a list of length %s"%\
                            self.degree())
            if coerce: 
                if len(entries) != 0:
                    coefficient_ring = parent.basis()[0][0].parent()
                    try:
                        entries = [coefficient_ring(x) for x in entries]
                    except TypeError:
                        raise TypeError("Unable to coerce entries (=%s) to coefficients in %s"%(entries, coefficient_ring))
            elif copy:
                # Make a copy
                entries = list(entries)
        self._entries = entries

    cpdef ModuleElement _add_(left, ModuleElement right):
        """
        Add left and right.

        EXAMPLES::

            sage: v = vector([1,2/3,pi]); w = vector([-2/3,pi^2,1])
            sage: v._add_(w)
            (1/3, pi^2 + 2/3, pi + 1)
        """
        cdef Py_ssize_t i, n
        n = PyList_Size(left._entries)
        v = [None]*n
        for i from 0 <= i < n:
            v[i] = (<RingElement>left._entries[i])._add_(<RingElement>
                                            ((<FreeModuleElement_generic_dense>right)._entries[i]))
        return left._new_c(v)

    cpdef ModuleElement _sub_(left, ModuleElement right):
        """
        Subtract right from left.
        
        EXAMPLES::
        
            sage: V = QQ^5
            sage: W = V.span([V.1, V.2])
            sage: W.0 - V.0
            (-1, 1, 0, 0, 0)
            sage: V.0 - W.0
            (1, -1, 0, 0, 0)
        """
        cdef Py_ssize_t i, n
        n = PyList_Size(left._entries)
        v = [None]*n
        for i from 0 <= i < n:
            v[i] = (<RingElement>left._entries[i])._sub_(<RingElement>
                                            ((<FreeModuleElement_generic_dense>right)._entries[i]))
        return left._new_c(v)

    cpdef ModuleElement _rmul_(self, RingElement left):
        """
        EXAMPLES::
        
            sage: V = ZZ['x']^5
            sage: 5 * V.0
            (5, 0, 0, 0, 0)
        """
        if left._parent is self._parent._base:
            v = [left._mul_(<RingElement>x) for x in self._entries]
        else:
            v = [left * x for x in self._entries]
        return self._new_c(v)

    cpdef ModuleElement _lmul_(self, RingElement right):
        """
        EXAMPLES::

            sage: v = vector([-1,0,3,pi])
            sage: v._lmul_(2/3)
            (-2/3, 0, 2, 2/3*pi)
            sage: v * (2/3)
            (-2/3, 0, 2, 2/3*pi)
        """
        if right._parent is self._parent._base:
            v = [(<RingElement>x)._mul_(right) for x in self._entries]
        else:
            v = [x * right for x in self._entries]
        return self._new_c(v)

    cpdef Element _dot_product_(left, element_Vector right):
        """
        Return the dot product of left and right.
        
        EXAMPLES::
        
            sage: R.<x> = QQ[]
            sage: v = vector([x,x^2,3*x]); w = vector([2*x,x,3+x])
            sage: v*w
            x^3 + 5*x^2 + 9*x
            sage: (x*2*x) + (x^2*x) + (3*x*(3+x))
            x^3 + 5*x^2 + 9*x
            sage: w*v
            x^3 + 5*x^2 + 9*x
        """
        return left.dot_product(right)

    cpdef element_Vector _pairwise_product_(left, element_Vector right): 
        """
        EXAMPLES::
        
            sage: R.<x> = QQ[]
            sage: v = vector([x,x^2,3*x]); w = vector([2*x,x,3+x])
            sage: v.pairwise_product(w)
            (2*x^2, x^3, 3*x^2 + 9*x)
            sage: w.pairwise_product(v)
            (2*x^2, x^3, 3*x^2 + 9*x)
        """
        if not right.parent() == left.parent():
            right = left.parent().ambient_module()(right)
        # Component wise vector * vector multiplication.
        cdef Py_ssize_t i, n
        n = PyList_Size(left._entries)
        v = [None]*n
        for i from 0 <= i < n:
            v[i] = (<RingElement>left._entries[i])._mul_((<FreeModuleElement_generic_dense>right)._entries[i])
        return left._new_c(v)

    def __reduce__(self):
        """
        EXAMPLES::

            sage: v = vector([-1,0,3,pi])
            sage: v.__reduce__()
            (<built-in function make_FreeModuleElement_generic_dense_v1>, (Vector space of dimension 4 over Symbolic Ring, [-1, 0, 3, pi], 4, True))        
        """
        return (make_FreeModuleElement_generic_dense_v1, (self._parent, self._entries, self._degree, self._is_mutable))

    def __getitem__(self, i):
        """
        EXAMPLES::

            sage: v = vector([RR(1), RR(2)]); v
            (1.00000000000000, 2.00000000000000)
            sage: v[0]
            1.00000000000000
            sage: v[-1]
            2.00000000000000
            sage: v[4]
            Traceback (most recent call last):
            ...
            IndexError: index must be between -2 and 1
            sage: v[-4]
            Traceback (most recent call last):
            ...
            IndexError: index must be between -2 and 1

            sage: v = vector(QQ['x,y'], [1,2, 'x*y'])
            sage: v
            (1, 2, x*y)
            sage: v[1:]
            (2, x*y)
        """
        if isinstance(i, slice):
            start, stop, step = i.indices(len(self))
            return vector(self.base_ring(), list(self)[start:stop:step])
        else:
            degree = self.degree()
            if i < 0:
                i += degree
            if i < 0 or i >= self.degree():
                raise IndexError("index must be between -%s and %s"%(degree, degree-1))
            return self._entries[i]

    def __setitem__(self, i, value):
        """
        Set entry i of self to value.

        EXAMPLES::

            sage: v = vector([1,2/3,pi])
            sage: v[1] = 19+pi
            sage: v
            (1, pi + 19, pi)
            sage: v = vector(QQ['x,y'], [1,2, 'x*y'])
            sage: v
            (1, 2, x*y)
            sage: v[1:]
            (2, x*y)
            sage: v[1:] = [4,5]; v
            (1, 4, 5)
            sage: v[:2] = [5,(6,2)]; v
            (5, 3, 5)
            sage: v[:2]
            (5, 3)
        """
        if not self._is_mutable:
            raise ValueError("vector is immutable; please change a copy instead (use copy())")
        cdef Py_ssize_t k, n, d
        if isinstance(i, slice):
            start, stop, step = i.indices(len(self))
            d = self.degree()
            R = self.base_ring()
            n = 0
            for k from start <= k < stop:
                if k >= d:
                    return
                if k >= 0:
                    self._entries[k] = R(value[n])
                    n = n + 1
        else:
            if i < 0 or i >= self.degree():
                raise IndexError("index (i=%s) must be between 0 and %s"%(i,
                                self.degree()-1))
            self._entries[i] = self.base_ring()(value)

    def list(self, copy=True):
        """
        Return list of elements of self.
        
        INPUT:

            - copy -- bool, return list of underlying entries
            
        EXAMPLES::

            sage: P.<x,y,z> = QQ[]
            sage: v = vector([x,y,z])
            sage: type(v)
            <type 'sage.modules.free_module_element.FreeModuleElement_generic_dense'>
            sage: a = v.list(); a
            [x, y, z]
            sage: a[0] = x*y; v
            (x, y, z)
            sage: a = v.list(copy=False); a
            [x, y, z]
            sage: a[0] = x*y; v
            (x*y, y, z)
        """
        if copy:
            return list(self._entries)
        else:
            return self._entries

    def __call__(self, *args, **kwargs):
        """
        Calling a free module element returns the result of calling each
        component.
        
        EXAMPLES::
        
            sage: x, y = var('x,y')
            sage: f = x^2 + y^2
            sage: g = f.gradient()
            sage: g
            (2*x, 2*y)
            sage: type(g)
            <class 'sage.modules.vector_symbolic_dense.Vector_symbolic_dense'>
            sage: g(y=2, x=3)
            (6, 4)
            sage: f(x,y) = x^2 + y^2
            sage: g = f.gradient()
            sage: g(3,2)
            (6, 4)
            sage: g(x=3, y=2)
            (6, 4)
        """
        return vector([e(*args, **kwargs) for e in self])

    def function(self, *args):
        """
        Returns a vector over a callable symbolic expression ring.

        EXAMPLES::

            sage: x,y=var('x,y')
            sage: v=vector([x,y,x*sin(y)])
            sage: w=v.function([x,y]); w
            (x, y) |--> (x, y, x*sin(y))
            sage: w.base_ring()
            Callable function ring with arguments (x, y)
            sage: w(1,2)
            (1, 2, sin(2))
            sage: w(2,1)
            (2, 1, 2*sin(1))
            sage: w(y=1,x=2)
            (2, 1, 2*sin(1))
            
        :: 

            sage: x,y=var('x,y')
            sage: v=vector([x,y,x*sin(y)])
            sage: w=v.function([x]); w
            x |--> (x, y, x*sin(y))
            sage: w.base_ring()    
            Callable function ring with arguments (x,)
            sage: w(4)
            (4, y, 4*sin(y))            
        """
        from sage.symbolic.callable import CallableSymbolicExpressionRing
        return vector(CallableSymbolicExpressionRing(args), self.list())

#############################################
# Generic sparse element
#############################################  
def _sparse_dot_product(v, w):
    """
    v and w are dictionaries with integer keys.

    EXAMPLES::

        sage: sage.modules.free_module_element._sparse_dot_product({0:5,1:7,2:3}, {0:-1, 2:2})
        1
    """
    x = set(v.keys()).intersection(set(w.keys()))
    return sum([v[k]*w[k] for k in x])
    
def make_FreeModuleElement_generic_sparse(parent, entries, degree):
    """
    EXAMPLES::

        sage: v = sage.modules.free_module_element.make_FreeModuleElement_generic_sparse(QQ^3, {2:5/2}, 3); v
        (0, 0, 5/2)
    """
    cdef FreeModuleElement_generic_sparse v
    v = FreeModuleElement_generic_sparse.__new__(FreeModuleElement_generic_sparse)
    v._entries = entries
    v._parent = parent
    v._degree = degree
    return v

def make_FreeModuleElement_generic_sparse_v1(parent, entries, degree, is_mutable):
    """
    EXAMPLES::
    
        sage: v = sage.modules.free_module_element.make_FreeModuleElement_generic_sparse_v1(QQ^3, {2:5/2}, 3, False); v
        (0, 0, 5/2)
        sage: v.is_mutable()
        False
    """
    cdef FreeModuleElement_generic_sparse v
    v = FreeModuleElement_generic_sparse.__new__(FreeModuleElement_generic_sparse)
    v._entries = entries
    v._parent = parent
    v._degree = degree
    v._is_mutable = is_mutable
    return v

cdef class FreeModuleElement_generic_sparse(FreeModuleElement):
    """
    A generic sparse free module element is a dictionary with keys ints
    i and entries in the base ring.
    
    EXAMPLES:
    
    Pickling works::
    
        sage: v = FreeModule(ZZ, 3, sparse=True).0
        sage: loads(dumps(v)) == v
        True
        sage: v = FreeModule(Integers(8)['x,y'], 5, sparse=True).1
        sage: loads(dumps(v)) - v
        (0, 0, 0, 0, 0)
    
    ::
    
        sage: a = vector([-1,0,1/1],sparse=True); b = vector([-1/1,0,0],sparse=True)
        sage: a.parent()
        Sparse vector space of dimension 3 over Rational Field
        sage: b - a
        (0, 0, -1)
        sage: (b-a).dict()
        {2: -1}
    """
    cdef _new_c(self, object v):
        # Create a new sparse free module element with minimal overhead and
        # no type checking.
        cdef FreeModuleElement_generic_sparse x
        x = PY_NEW(FreeModuleElement_generic_sparse)
        x._is_mutable = 1
        x._parent = self._parent
        x._entries = v
        x._degree = self._degree
        return x

    cdef bint is_dense_c(self):
        return 0
       
    cdef bint is_sparse_c(self):
        return 1

    def __copy__(self):
        """
        EXAMPLES::
        
            sage: v = vector([1,2/3,pi], sparse=True)
            sage: v.__copy__()
            (1, 2/3, pi)
        """
        return self._new_c(dict(self._entries))

    def __init__(self, parent, 
                 entries=0, 
                 coerce=True, 
                 copy=True):
        """
        EXAMPLES::

            sage: v = sage.modules.free_module_element.FreeModuleElement_generic_sparse(VectorSpace(QQ,3,sparse=True), {1:5/4}); v
            (0, 5/4, 0)
            sage: v.is_sparse()
            True

        TESTS:

        Test that 11751 is fixed::

            sage: K.<x> = QQ[]
            sage: M = FreeModule(K, 1, sparse=True)
            sage: N = M.span([{0:1/x}]); N
            Sparse free module of degree 1 and rank 1 over Univariate Polynomial Ring in x over Rational Field
            Echelon basis matrix:
            [1/x]
            sage: N({0:1/x}) # this used to fail prior to #11751
            (1/x)
            sage: N({0:1/x^2})
            Traceback (most recent call last):
            ...
            TypeError: element (= {0: 1/x^2}) is not in free module

        ::

            sage: L = FreeModule(K, 2, sparse=True)
            sage: R = L.span([{0:x, 1:0}, {0:0, 1:1/x}], check=False, already_echelonized=True)
            sage: R.basis()[0][0].parent()
            Fraction Field of Univariate Polynomial Ring in x over Rational Field
            sage: R = L.span([{0:x, 1:x^2}])
            sage: R.basis()[0][0].parent()
            Univariate Polynomial Ring in x over Rational Field
        """
        #WARNING: In creation, we do not check that the i pairs satisfy
        #     0 <= i < degree.
        FreeModuleElement.__init__(self, parent)
        R = self.base_ring()
        if entries == 0:
            entries = {}
        else:
            if isinstance(entries, list):
                if len(entries) != self.degree():
                    raise TypeError("entries has the wrong length")
                x = entries
                entries = {}
                for i in xrange(self.degree()):
                    if x[i] != 0:
                        entries[i] = x[i]
                copy = False
            if not isinstance(entries, dict):
                raise TypeError, "entries must be a dict"
            if copy:
                # Make a copy
                entries = dict(entries)
            if coerce:
                if len(entries) != 0:
                    coefficient_ring = parent.basis()[0][0].parent()
                    try:
                        for k, x in entries.iteritems():
                            entries[k] = coefficient_ring(x)
                    except TypeError:
                        raise TypeError("Unable to coerce value (=%s) of entries dict (=%s) to %s"%(x, entries, coefficient_ring))
        self._entries = entries

    cpdef ModuleElement _add_(left, ModuleElement right):
        """
        Add left and right.

        EXAMPLES::
        
            sage: v = vector([1,2/3,pi], sparse=True)
            sage: v._add_(v)
            (2, 4/3, 2*pi)
        """
        cdef object v, e
        e = dict((<FreeModuleElement_generic_sparse>right)._entries)
        for i, a in left._entries.iteritems():
            if e.has_key(i):
                sum = (<RingElement>a)._add_(<RingElement> e[i])
                if sum:
                    e[i] = sum
                else:
                    del e[i]
            elif a:
                e[i] = a
        return left._new_c(e)

    cpdef ModuleElement _sub_(left, ModuleElement right):
        """
        EXAMPLES::
        
            sage: v = vector([1,2/3,pi], sparse=True)
            sage: v._sub_(v)
            (0, 0, 0)
        """
        cdef object v, e
        e = dict(left._entries)   # dict to make a copy
        for i, a in (<FreeModuleElement_generic_sparse>right)._entries.iteritems():
            if e.has_key(i):
                diff = (<RingElement> e[i])._sub_(<RingElement>a)
                if diff:
                    e[i] = diff
                else:
                    del e[i]
            elif a:
                e[i] = -a
        return left._new_c(e)

    cpdef ModuleElement _lmul_(self, RingElement right):
        """
        EXAMPLES::

            sage: v = vector([1,2/3,pi], sparse=True)
            sage: v._lmul_(SR(3))
            (3, 2, 3*pi)
        """
        cdef object v
        v = PyDict_New()
        if right:
            for i, a in self._entries.iteritems():
                prod = (<RingElement>a)._mul_(right)
                if prod:
                    v[i] = prod
        return self._new_c(v)

    cpdef ModuleElement _rmul_(self, RingElement left):
        """
        EXAMPLES::

            sage: v = vector([1,2/3,pi], sparse=True)
            sage: v._rmul_(SR(3))
            (3, 2, 3*pi)
        """
        cdef object v
        v = PyDict_New()
        if left:
            for i, a in self._entries.iteritems():
                prod = left._mul_(a)
                if prod:
                    v[i] = prod
        return self._new_c(v)

    cpdef Element _dot_product_(left, element_Vector right):
        """
        Return the dot product of left and right.
        
        EXAMPLES::
        
            sage: v = vector([1,2,0], sparse=True); w = vector([0,5,-9], sparse=True)
            sage: v * w
            10
            sage: w * v
            10
        """
        cdef object v, e, z
        e = dict((<FreeModuleElement_generic_sparse>right)._entries)
        z = left.base_ring()(0)
        for i, a in left._entries.iteritems():
            if e.has_key(i):            
                z += (<RingElement>a)._mul_(<RingElement> e[i])
        return z

    cpdef element_Vector _pairwise_product_(left, element_Vector right):
        """
        EXAMPLES::
        
            sage: v = vector([1,2/3,pi], sparse=True); w = vector([-2/3,pi^2,1],sparse=True)
            sage: v._pairwise_product_(w)
            (-2/3, 2/3*pi^2, pi)
        """
        # Component wise vector * vector multiplication.
        cdef object v, e
        e = dict((<FreeModuleElement_generic_sparse>right)._entries)
        v = PyDict_New()
        for i, a in left._entries.iteritems():
            if e.has_key(i):
                prod = (<RingElement>a)._mul_(<RingElement> e[i])
                if prod:
                    v[i] = prod
        return left._new_c(v)

    cdef int _cmp_c_impl(left, Element right) except -2:
        """
        Compare two sparse free module elements.

        Free module elements are compared in lexicographic order on
        the underlying list of coefficients. Two free module elements
        are equal if their coefficients are the same. (This is true
        even if one is sparse and one is dense.)

        TESTS::

            sage: v = vector([1,2/3,pi], sparse=True)
            sage: w = vector([1,2/3,pi], sparse=True)
            sage: w == v
            True
        """
        a = left._entries.items()
        a.sort()
        b = (<FreeModuleElement_generic_dense>right)._entries.items()
        b.sort()
        return cmp(a,b)

    # see sage/structure/element.pyx
    def __richcmp__(left, right, int op):
        """
        TESTS::

            sage: v = vector([1,2/3,pi], sparse=True)
            sage: v == v
            True
        """
        return (<Element>left)._richcmp(right, op)

    # __hash__ is not properly inherited if comparison is changed
    def __hash__(self):
        """
        TESTS::

            sage: v = vector([1,2/3,pi], sparse=True)
            sage: v.set_immutable()
            sage: isinstance(hash(v), int)
            True
        """
        return FreeModuleElement.__hash__(self)

    def iteritems(self):
        """
        Return iterator over the entries of self.

        EXAMPLES::

            sage: v = vector([1,2/3,pi], sparse=True)
            sage: v.iteritems()
            <dictionary-itemiterator object at ...>
            sage: list(v.iteritems())
            [(0, 1), (1, 2/3), (2, pi)]
        """
        return self._entries.iteritems()
    
    def __reduce__(self):
        """
        EXAMPLES::

            sage: v = vector([1,2/3,pi], sparse=True)
            sage: v.__reduce__()
            (<built-in function make_FreeModuleElement_generic_sparse_v1>, (Sparse vector space of dimension 3 over Symbolic Ring, {0: 1, 1: 2/3, 2: pi}, 3, True))
        """
        return (make_FreeModuleElement_generic_sparse_v1, (self._parent, self._entries, self._degree, self._is_mutable))

    def __getitem__(self, i):
        """
        EXAMPLES::
        
            sage: v = vector([RR(1), RR(2)], sparse=True); v
            (1.00000000000000, 2.00000000000000)
            sage: v[0]
            1.00000000000000
            sage: v[-1]
            2.00000000000000
            sage: v[5]
            Traceback (most recent call last):
            ...
            IndexError: index must be between -2 and 1
            sage: v[-3]
            Traceback (most recent call last):
            ...
            IndexError: index must be between -2 and 1
        """
        if isinstance(i, slice):
            start, stop, step = i.indices(len(self))
            return vector(self.base_ring(), self.list()[start:stop])
        else:
            i = int(i)
            degree = self.degree()
            if i < 0:
                i += degree
            if i < 0 or i >= degree:
                raise IndexError("index must be between %s and %s"%(-degree,
                                degree-1))
            if self._entries.has_key(i):
                return self._entries[i]
            return self.base_ring()(0)  # optimize this somehow
        
    def get(self, i):
        """
        Like __getitem__ but with no guaranteed type or bounds checking. Returns 0
        if access is out of bounds.

        EXAMPLES::

            sage: v = vector([1,2/3,pi], sparse=True)
            sage: v.get(1)
            2/3
            sage: v.get(10)
            0
        """
        i = int(i)
        if self._entries.has_key(i):
            return self._entries[i]
        return self.base_ring()(0)  # optimize this somehow

        
    def set(self, i, x):
        """
        Like __setitem__ but with no guaranteed type or bounds checking.

        EXAMPLES::

            sage: v = vector([1,2/3,pi], sparse=True)
            sage: v.set(1, pi^3)
            sage: v
            (1, pi^3, pi)

        No bounds checking::
        
            sage: v.set(10, pi)

        This lack of bounds checking causes trouble later::
        
            sage: v
            Traceback (most recent call last):
            ...
            IndexError: list assignment index out of range
        """
        if not self._is_mutable:
            raise ValueError("vector is immutable; please change a copy instead (use copy())")
        i = int(i)
        if x == 0:
            if self._entries.has_key(i):
                del self._entries[i]
            return
        self._entries[i] = x
    
    def __setitem__(self, i, value):
        """
        Set the `i`-th entry or slice of self to value.

        EXAMPLES::

            sage: V = VectorSpace(GF(17), 10000000, sparse=True)
            sage: w = V(0)
            sage: w[39893] = 20
            sage: w[39893]
            3
            sage: w[39000:39003] = [4, 5, 6]; w[39000:39003]
            (4, 5, 6)
            sage: parent(w[39893])
            Finite Field of size 17
            sage: w[39893] = sqrt(2)
            Traceback (most recent call last):
            ...
            TypeError: unable to convert x (=sqrt(2)) to an integer
        """
        if not self._is_mutable:
            raise ValueError("vector is immutable; please change a copy instead (use copy())")
        cdef Py_ssize_t k, d, n
        if isinstance(i, slice):
            start, stop = i.start, i.stop
            d = self.degree()
            R = self.base_ring()
            n = 0
            for k from start <= k < stop:
                if k >= d:
                    return
                if k >= 0:
                    self[k] = R(value[n])
                    n = n + 1
        else:
            i = int(i)
            if i < 0 or i >= self.degree():
                raise IndexError("index (i=%s) must be between 0 and %s"%(i,
                                self.degree()-1))
            self.set(i, self._parent.base_ring()(value))

    def denominator(self):
        """
        Return the least common multiple of the denominators of the
        entries of self.

        EXAMPLES::

            sage: v = vector([1/2,2/5,3/14], sparse=True)
            sage: v.denominator()
            70
        """
        R = self.base_ring()
        x = self._entries
        if len(x) == 0:
            return 1
        Z = x.iteritems()
        d = Z.next()[1].denominator()
        for _, y in Z:
            d = d.lcm(y.denominator())
        return d
        
    def dict(self, copy=True):
        """
        Return dictionary of nonzero entries of self.

        INPUT:

            - ``copy`` -- bool (default: True)

        OUTPUT:

            - Python dictionary

        EXAMPLES::

            sage: v = vector([0,0,0,0,1/2,0,3/14], sparse=True)
            sage: v.dict()
            {4: 1/2, 6: 3/14}
        """
        if copy:
            return dict(self._entries)
        else:
            return self._entries

    def list(self, copy=True):
        """
        Return list of elements of self.
        
        INPUT:

            - copy -- bool, return list of underlying entries
            
        EXAMPLES::

            sage: v = vector([1,2/3,pi], sparse=True)
            sage: type(v)
            <type 'sage.modules.free_module_element.FreeModuleElement_generic_sparse'>
            sage: a = v.list(); a
            [1, 2/3, pi]
        """
        cdef Py_ssize_t n
        n = self._parent.degree()
        z = self._parent.base_ring()(0)
        v = [z]*n
        for i, a in self._entries.iteritems():
            v[i] = a
        return v

    def nonzero_positions(self):
        """
        Returns the list of numbers ``i`` such that ``self[i] != 0``.

        EXAMPLES::
        
            sage: v = vector({1: 1, 3: -2})
            sage: w = vector({1: 4, 3: 2})
            sage: v+w
            (0, 5, 0, 0)
            sage: (v+w).nonzero_positions()
            [1]
        """
        K = self._entries.keys()
        K.sort()
        return K

    cpdef int hamming_weight(self):
        """
        Returns the number of positions ``i`` such that ``self[i] != 0``.

        EXAMPLES::

            sage: v = vector({1: 1, 3: -2})
            sage: w = vector({1: 4, 3: 2})
            sage: v+w
            (0, 5, 0, 0)
            sage: (v+w).hamming_weight()
            1
        """
        return len(self._entries)

    def _numerical_approx(self, prec=None, digits=None):
        """
        Returns a numerical approximation of self by calling the n() method
        on all of its entries.
        
        EXAMPLES::
        
            sage: v = vector(RealField(200), [1,2,3], sparse=True)
            sage: v.n()
            (1.00000000000000, 2.00000000000000, 3.00000000000000)
            sage: _.parent()
            Sparse vector space of dimension 3 over Real Field with 53 bits of precision
            sage: v.n(prec=75)
            (1.000000000000000000000, 2.000000000000000000000, 3.000000000000000000000)
            sage: _.parent()
            Sparse vector space of dimension 3 over Real Field with 75 bits of precision
        """
        return vector(dict([(e[0],e[1].n(prec, digits)) for e in self._entries.iteritems()]), sparse=True)


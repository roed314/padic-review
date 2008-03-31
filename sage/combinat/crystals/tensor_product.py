r"""
Tensor products of crystals
"""

#*****************************************************************************
#       Copyright (C) 2007 Anne Schilling <anne at math.ucdavis.edu>
#                          Nicolas Thiery <nthiery at users.sf.net>
#
#  Distributed under the terms of the GNU General Public License (GPL)
#
#    This code is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#    General Public License for more details.
#
#  The full text of the GPL is available at:
#
#                  http://www.gnu.org/licenses/
#****************************************************************************

from sage.misc.latex           import latex
from sage.structure.element    import Element
from sage.combinat.cartan_type import CartanType
from sage.combinat.cartesian_product  import CombinatorialObject, CartesianProduct
from sage.combinat.partition   import Partition
from sage.combinat.tableau     import Tableau
from crystals                  import Crystal, CrystalElement, ClassicalCrystal
from letters                   import CrystalOfLetters
from sage.misc.flatten         import flatten
from sage.rings.integer        import Integer
from sage.misc.mrange          import xmrange_iter

##############################################################################
# Support classes
##############################################################################

class ImmutableListWithParent(CombinatorialObject, Element):
    r"""
    A class for lists having a parent

    Specification: any subclass C should implement __init__ which accepts the following 
    form C(parent, list = list)

    We create an immutable list whose parent is the class list:

    sage: from sage.combinat.crystals.tensor_product import ImmutableListWithParent
    sage: l = ImmutableListWithParent(list, [1,2,3])

    TESTS:

    sage: l._list == [1, 2, 3]
    True
    sage: l.parent() == list
    True
    sage: l == l
    True
    sage: l.sibling([2,1]) == ImmutableListWithParent(list, [2,1])
    True
    sage: l.reverse()      == l.sibling([3,2,1])
    True
    sage: l.set_index(1,4) == l.sibling([1,4,3])
    True

    """

    def __init__(self, parent, list):
#        Element.__init__(self, parent);
        self._parent = parent
        CombinatorialObject.__init__(self, list)

    def parent(self):
        return self._parent  # Should be inherited from Element!

    def __repr__(self):
        return "%s"%self._list

    def __eq__(self, other):
        return self.__class__ == other.__class__ and \
               self.parent()  == self.parent()   and \
               self._list      == other._list

    def sibling(self, list): # Makes some hypothesis on the constructor!
                             # of subclasses
        return self.__class__(self.parent(), list=list)

    def reverse(self):
        return self.sibling([ i for i in reversed(self._list)])

    def set_index(self, k, value):
        l = [i for i in self._list]
        l[k] = value
        return self.sibling(l)

# FIXME: should be, or not, in ClassicalCrystal depending on the input
class TensorProductOfCrystals(ClassicalCrystal):
    r"""
    Tensor product of crystals.

    EXAMPLES:

        We construct the type $A_2$-crystal generated by $2\otimes
        1\otimes 1$:
    
        sage: C = CrystalOfLetters(['A',2])
        sage: T = TensorProductOfCrystals(C,C,C,generators=[[C(2),C(1),C(1)]])

        It has $8$ elements

        sage: [t for t in T]                                                  
        [[2, 1, 1],
        [2, 1, 2],
        [2, 1, 3],
        [3, 1, 3],
        [3, 2, 3],
        [3, 1, 1],
        [3, 1, 2],
        [3, 2, 2]]

        sage: C = CrystalOfTableaux(['A',3], shape=[1,1,0])
        sage: D = CrystalOfTableaux(['A',3], shape=[1,0,0])
        sage: T = TensorProductOfCrystals(C,D,generators="all")
        sage: T.count()
        24
        sage: T.check()
        True
        sage: T.module_generators
        [[[[1], [2]], [[1]]], [[[2], [3]], [[1]]]]
        sage: [x.weight() for x in T.module_generators]
        [(2, 1, 0, 0), (1, 1, 1, 0)]

    TESTS:
        sage: C = CrystalOfLetters(['A',5])
        sage: T = TensorProductOfCrystals(C,C)

        sage: T(C(1),C(2)).e(1) == T(C(1),C(1))
        True
        sage: T(C(2),C(1)).e(1) == None
        True
        sage: T(C(2),C(2)).e(1) == T(C(1),C(2))
        True

	sage: T(C(1),C(1)).f(1) == T(C(1),C(2))
	True
	sage: T(C(2),C(1)).f(1) == None
	True
	sage: T(C(1),C(2)).f(1) == T(C(2),C(2))
	True

	sage: T(C(2),C(1)).positionsOfUnmatchedMinus(1) == []
	True
	sage: T(C(2),C(1)).positionsOfUnmatchedPlus(1) == []
	True
	sage: T(C(1),C(2)).positionsOfUnmatchedMinus(1) == [0]
	True
	sage: T(C(1),C(2)).positionsOfUnmatchedPlus(1) == [1]
	True

        sage: T.check()   # module generators not implemented
        True
    """
    def __init__(self, *crystals, **options):
        crystals = [ crystal for crystal in crystals]
        self._name = "The tensor product of the crystals %s"%crystals
        self.crystals = crystals
	if options.has_key('cartan_type'):
	    self.cartanType = CartanType(options['cartan_type'])
	else:
	    if len(crystals) == 0:
		raise ValueError, "you need to specify the Cartan type if the tensor product list is empty"
	    else:
		self.cartanType = crystals[0].cartanType
        self.index_set = self.cartanType.index_set()
        if options.has_key('generators'):
            if options['generators'] == "all":
                self.module_generators = []
                for c in list(xmrange_iter([D.list() for D in crystals])):
                    candidate = self(*c)
                    if all(candidate.e(k) == None for k in self.index_set):
                        self.module_generators.append(candidate)
            else:
                self.module_generators = [ self(*x) for x in options['generators']]

    def __call__(self, *args):
        return TensorProductOfCrystalsElement(self,
                                              [crystalElement for crystalElement in args]);

class TensorProductOfCrystalsElement(ImmutableListWithParent, CrystalElement):
    r"""
    A class for elements of tensor products of crystals
    """
    
    def e(self, i):
	assert i in self.index_set()
	position = self.positionsOfUnmatchedPlus(i)
	if position == []:
	    return None
	k = position[0]
	return self.set_index(k, self[k].e(i))
    
    def f(self, i):
	assert i in self.index_set()
	position = self.positionsOfUnmatchedMinus(i)
	if position == []:
	    return None
	k = position[len(position)-1]
	return self.set_index(k, self[k].f(i))

    def phi(self, i):
	self = self.reverse()
	height = 0
	for j in range(len(self)):
	    plus = self[j].epsilon(i)
	    minus = self[j].phi(i)
	    if height-plus < 0:
		height = minus
	    else:
		height = height - plus + minus
	return height	
    
    def epsilon(self, i):
	height = 0
	for j in range(len(self)):
	    minus = self[j].phi(i)
	    plus = self[j].epsilon(i)
	    if height-minus < 0:
		height = plus
	    else:
		height = height - minus + plus
	return height

    def positionsOfUnmatchedMinus(self, i, dual=False, reverse=False):
	unmatchedPlus = []
	height = 0
	if reverse == True:
	    self = self.reverse()
	if dual == False:
	    for j in range(len(self)):
		minus = self[j].phi(i)
		plus = self[j].epsilon(i)
		if height-minus < 0:
		    unmatchedPlus.append(j)
		    height = plus
		else:
		    height = height - minus + plus
	else:
	    for j in range(len(self)):
		plus = self[j].epsilon(i)
		minus = self[j].phi(i)
		if height-plus < 0:
		    unmatchedPlus.append(j)
		    height = minus
		else:
		    height = height - plus + minus
	return unmatchedPlus

    def positionsOfUnmatchedPlus(self, i):
	list = self.positionsOfUnmatchedMinus(i, dual=True, reverse=True)
	list.reverse()
	return [len(self)-1-list[j] for j in range(len(list))]
	
class CrystalOfTableaux(TensorProductOfCrystals):
    r"""
    Crystals of tableaux. Input: a Cartan Type type and "shape",
    a partition of length <= type[1]. Produces a classical crystal with
    the given Cartan Type and highest weight corresponding to the
    given shape.

    If the type is ['D',r] then the shape is permitted to have
    a negative value in the r-th position. Thus if shape=$[s_1,s_2,...,s_r]$
    then s_r may be negative but in any case
    $s1 \ge s2 \ge ... s_{r-1} \ge |s_r|$. This crystal is
    related to $[s_1,\cdots,|s_r|]$ by the outer automorphism
    of SO(2r).

    EXAMPLES:

        We create the crystal of tableaux for type $A_2$, with highest
        weight given by the partition [2,1,1].

        sage: Tab = CrystalOfTableaux(['A',3], shape = [2,1,1])

        Here is the list of its elements:
        
        sage: Tab.list()
        [[[1, 1], [2], [3]], [[1, 2], [2], [3]], [[1, 3], [2], [3]], 
         [[1, 4], [2], [3]], [[1, 4], [2], [4]], [[1, 4], [3], [4]], 
         [[2, 4], [3], [4]], [[1, 1], [2], [4]], [[1, 2], [2], [4]], 
         [[1, 3], [2], [4]], [[1, 3], [3], [4]], [[2, 3], [3], [4]], 
         [[1, 1], [3], [4]], [[1, 2], [3], [4]], [[2, 2], [3], [4]]]

        One can get (currently) crude ploting via:

#        sage: Tab.plot()  # random

        One can get instead get a LaTeX drawing ready to be
        copy-pasted into a LaTeX file:

#        sage: Tab.latex() # random

        See sage.combinat.crystals? for general help on using crystals

	Internally, a tableau of a given Cartan type is represented as a tensor 
	product of letters of the same type. The order in which the tensor factors
	appear is by reading the columns of the tableaux left to right, top to bottom. 
	As an example:
	sage: T = CrystalOfTableaux(['A',2], shape = [3,2])
	sage: T.module_generators[0]
	[[1, 1, 1], [2, 2]]
	sage: T.module_generators[0]._list
	[2, 1, 2, 1, 1]

        To create a tableau, one can use:
        sage: Tab = CrystalOfTableaux(['A',3], shape = [2,2])
        sage: Tab(rows    = [[1,2],[3,4]])
        [[1, 2], [3, 4]]
        sage: Tab(columns = [[3,1],[4,2]])
        [[1, 2], [3, 4]]

        FIXME: do we want to specify the columns increasingly or decreasingly
        That is, should this be Tab(columns = [[1,3],[2,4]])

        TODO: make this fully consistent with Tableau!

    TESTS:

        Base cases:
        
        sage: Tab = CrystalOfTableaux(['A',2], shape = [])
	sage: Tab.list()
	[[]]
        sage: Tab = CrystalOfTableaux(['C',2], shape = [1])
	sage: Tab.check()
	True
        sage: Tab.list()
	[[[1]], [[2]], [[-2]], [[-1]]]

        Input tests:

        sage: Tab = CrystalOfTableaux(['A',3], shape = [2,2])
        sage: C = Tab.letters
        sage: Tab(rows    = [[1,2],[3,4]])._list == [C(3),C(1),C(4),C(2)]
        True
        sage: Tab(columns = [[3,1],[4,2]])._list == [C(3),C(1),C(4),C(2)]
        True

        And for compatibility with TensorProductOfCrystal we should
        also allow as input the internal list / sequence of elements:
        
        sage: Tab(list    = [3,1,4,2])._list     == [C(3),C(1),C(4),C(2)]
        True
        sage: Tab(3,1,4,2)._list                 == [C(3),C(1),C(4),C(2)]
        True
        
        Type D, illustrating that the last parameter in the shape can
        be negative:

        sage: C = CrystalOfTableaux(['D',4],shape=[1,1,1,-1])
        sage: C.count()
        35
        sage: C.check()
        True

    """
    def __init__(self, type, shape):
	self.letters = CrystalOfLetters(type)
        if type[0] == 'D' and len(shape) == type[1] and shape[type[1]-1] < 0:
            invert = True
            shape[type[1]-1]=-shape[type[1]-1]
        else:
            invert = False
        shape = Partition(shape)
        if not all(shape[i] <= shape[i-1] for i in range(1,len(shape))):
            raise ValueError, "shape must be a partition"
	p = shape.conjugate()
        # The column canonical tableau, read by columns
	module_generator = flatten([[p[j]-i for i in range(p[j])] for j in range(len(p))])
        if invert:
            for i in range(type[1]):
                if module_generator[i] == type[1]:
                    module_generator[i] = -type[1]
        module_generator=[self.letters(x) for x in module_generator]
	TensorProductOfCrystals.__init__(self, *[self.letters]*shape.size(), **{'generators':[module_generator],'cartan_type':type})
	self._name = "The crystal of tableaux of type %s and shape %s"%(type, str(shape))
	self.shape = shape

    def __call__(self, *args, **options):
        return CrystalOfTableauxElement(self, *args, **options);

class CrystalOfTableauxElement(TensorProductOfCrystalsElement):
    def __init__(self, parent, *args, **options):
        if len(args) == 1 and isinstance(args[0], CrystalOfTableauxElement):
            if args[0].parent() == parent:
                return args[0];
            else:
                raise ValueError, "Inconsistent parent"
	if options.has_key('list'):
	    list = options['list']
	elif options.has_key('rows'):
	    rows=options['rows']
	    list=Tableau(rows).to_word_by_column()
	elif options.has_key('columns'):
	    columns=options['columns']
	    list=[]
	    for col in columns:
		list+=col
	else:
	    list = [i for i in args]
	if list <> [] and type(list[0]) == Integer:
	    list=[parent.letters(x) for x in list]
	TensorProductOfCrystalsElement.__init__(self, parent, list=list)

    def __repr__(self):
	return repr(self.to_tableau())

    def _latex_(self):
	return latex(self.to_tableau())

    def to_tableau(self):
	shape = self.parent().shape.conjugate()
	tab = []
	s = 0
	for i in range(len(shape)):
	    col = [ self[s+k] for k in range(shape[i]) ]
	    col.reverse()
	    s += shape[i]
	    tab.append(col)
	tab = Tableau(tab)
	return(tab.conjugate())


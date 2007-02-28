"""
Multidimensional enumeration

AUTHORS:
    -- Joel B. Mohler (2006-10-12)
    -- William Stein (2006-07-19)
    -- Jon Hanke
"""

########################################################################
#       Copyright (C) 2006 William Stein <wstein@gmail.com>
#
#  Distributed under the terms of the GNU General Public License (GPL)
#
#                  http://www.gnu.org/licenses/
########################################################################

import misc

def _xmrange_iter( iter_list, typ=list ):
    if len(iter_list) == 0:
        return
    curr_iters = [i.__iter__() for i in iter_list]
    curr_elt = [iter.next() for iter in curr_iters[:-1]] + [None]
    place = len(iter_list) - 1
    while True:
        try:
            while True:
                curr_elt[place] = curr_iters[place].next()
                if place < len(iter_list) - 1:
                    place += 1
                    curr_iters[place] = iter_list[place].__iter__()
                    continue
                else:
                    yield typ(curr_elt)
        except StopIteration:
            place -= 1
            if place == -1:
                return

def mrange_iter(iter_list, typ=list):
    """
    Return the multirange list derived from the given list of iterators.

    This is the list version of xmrange_iter.  Use xmrange_iter for the
    iterator.

    More precisely, return the iterator over all objects of type typ
    of n-tuples of Python ints with entries between 0 and the integers
    in the sizes list.  The iterator is empty if sizes is empty or
    contains any non-positive integer.

    INPUT:
        sizes -- a list of nonnegative integers
        typ -- (default: list) a type or class; more generally,
               something that can be called with a list as input.

    OUTPUT:
        a list

    EXAMPLES:
        sage: mrange_iter([range(3),[0,2]])
        [[0, 0], [0, 2], [1, 0], [1, 2], [2, 0], [2, 2]]
        sage: mrange_iter([['Monty','Flying'],['Python','Circus']], tuple)
        [('Monty', 'Python'), ('Monty', 'Circus'), ('Flying', 'Python'), ('Flying', 'Circus')]
        sage: mrange_iter([[2,3,5,7],[1,2]], sum)
        [3, 4, 4, 5, 6, 7, 8, 9]

    Examples that illustrate empty multi-ranges. 
        sage: mrange_iter([])
        []
        sage: mrange_iter([range(5),xrange(3),xrange(-2)])
        []
        sage: mrange_iter([range(5),range(3),range(0)])
        []

    AUTHORS:
        -- Joel B. Mohler
    """
    return list(_xmrange_iter(iter_list, typ))

class xmrange_iter:
    """
    Return the multirange iterate derived from the given iterators 
    and type.

    NOTE: This basically gives you the cartesian product of sets.

    More precisely, return the iterator over all objects of type typ
    of n-tuples of Python ints with entries between 0 and the integers
    in the sizes list.  The iterator is empty if sizes is empty or
    contains any non-positive integer.

    Use mrange_iter for the non-iterator form.

    INPUT:
        list_iter -- a list of objects usable as iterators (possibly lists)
        typ -- (default: list) a type or class; more generally,
               something that can be called with a list as input.

    OUTPUT:
        a generator

    EXAMPLES:
    We create multi-range iterators, print them and also iterate
    through a tuple version.
        sage: z = xmrange_iter([xrange(3),xrange(2)]);z
        xmrange_iter([xrange(3), xrange(2)])
        sage: z = xmrange_iter([range(3),range(2)], tuple);z
        xmrange_iter([[0, 1, 2], [0, 1]], <type 'tuple'>)
        sage: for a in z:
        ...    print a
        (0, 0)
        (0, 1)
        (1, 0)
        (1, 1)
        (2, 0)
        (2, 1)

    We illustrate a few more iterations.
        sage: list(xmrange_iter([range(3),range(2)]))
        [[0, 0], [0, 1], [1, 0], [1, 1], [2, 0], [2, 1]]
        sage: list(xmrange_iter([range(3),range(2)], tuple))
        [(0, 0), (0, 1), (1, 0), (1, 1), (2, 0), (2, 1)]

    Here we compute the sum of each element of the multi-range iterator:
        sage: list(xmrange_iter([range(3),range(2)], sum))
        [0, 1, 1, 2, 2, 3]

    Next we compute the product:
        sage: list(xmrange_iter([range(3),range(2)], prod))
        [0, 0, 0, 1, 0, 2]
        
    Examples that illustrate empty multi-ranges. 
        sage: list(xmrange_iter([]))
        []
        sage: list(xmrange_iter([xrange(5),xrange(3),xrange(-2)]))
        []
        sage: list(xmrange_iter([xrange(5),xrange(3),xrange(0)]))
        []

    We use a multi-range iterator to iterate through the cartesian
    product of sets.
        sage: X = ['red', 'apple', 389]
        sage: Y = ['orange', 'horse']
        sage: for i,j in xmrange_iter([X, Y], tuple):
        ...    print (i, j)
        ('red', 'orange')
        ('red', 'horse')
        ('apple', 'orange')
        ('apple', 'horse')
        (389, 'orange')
        (389, 'horse')

    AUTHORS:
        -- Joel B. Mohler
    """
    def __init__(self, iter_list, typ=list):
        self.iter_list = iter_list
        self.typ = typ

    def __repr__(self):
        if self.typ == list:
            return 'xmrange_iter(%s)'%self.iter_list
        else:
            return 'xmrange_iter(%s, %s)'%(self.iter_list, self.typ)

    def __iter__(self):
        return _xmrange_iter(self.iter_list, self.typ)



def _xmrange(sizes, typ=list):
    n = len(sizes)
    if n == 0:
        return
    for i in sizes:
        if i <= 0:
            return
    v = [0] * n    # make a list of n 0's.
    v[-1] = -1
    ptr_max = n - 1
    ptr = ptr_max
    while True:
        while True:
            if ptr != -1 and v[ptr] + 1 < sizes[ptr]:
                v[ptr] += 1
                ptr = ptr_max
                break
            elif ptr != -1:
                v[ptr] = 0
                ptr -= 1
            else:
                return
        yield typ(v)   # make a copy of v!


def mrange(sizes, typ=list):
    """
    Return the multirange list with given sizes and type.

    This is the list version of xmrange.  Use xmrange for the
    iterator.
    
    More precisely, return the iterator over all objects of type typ
    of n-tuples of Python ints with entries between 0 and the integers
    in the sizes list.  The iterator is empty if sizes is empty or
    contains any non-positive integer.

    INPUT:
        sizes -- a list of nonnegative integers
        typ -- (default: list) a type or class; more generally,
               something that can be called with a list as input.

    OUTPUT:
        a list

    EXAMPLES:
        sage: mrange([3,2])
        [[0, 0], [0, 1], [1, 0], [1, 1], [2, 0], [2, 1]]
        sage: mrange([3,2], tuple)
        [(0, 0), (0, 1), (1, 0), (1, 1), (2, 0), (2, 1)]
        sage: mrange([3,2], sum)
        [0, 1, 1, 2, 2, 3]

    Examples that illustrate empty multi-ranges. 
        sage: mrange([])
        []
        sage: mrange([5,3,-2])
        []
        sage: mrange([5,3,0])
        []        
               
    AUTHORS:
        -- Jon Hanke
        -- William Stein
    """
    return list(_xmrange(sizes, typ))


class xmrange:
    """
    Return the multirange iterate with given sizes and type.
    
    More precisely, return the iterator over all objects of type typ
    of n-tuples of Python ints with entries between 0 and the integers
    in the sizes list.  The iterator is empty if sizes is empty or
    contains any non-positive integer.

    Use mrange for the non-iterator form.

    INPUT:
        sizes -- a list of nonnegative integers
        typ -- (default: list) a type or class; more generally,
               something that can be called with a list as input.

    OUTPUT:
        a generator

    EXAMPLES:
    We create multi-range iterators, print them and also iterate
    through a tuple version.
        sage: z = xmrange([3,2]);z
        xmrange([3, 2])
        sage: z = xmrange([3,2], tuple);z
        xmrange([3, 2], <type 'tuple'>)
        sage: for a in z:
        ...    print a
        (0, 0)
        (0, 1)
        (1, 0)
        (1, 1)
        (2, 0)
        (2, 1)

    We illustrate a few more iterations.
        sage: list(xmrange([3,2]))
        [[0, 0], [0, 1], [1, 0], [1, 1], [2, 0], [2, 1]]
        sage: list(xmrange([3,2], tuple))
        [(0, 0), (0, 1), (1, 0), (1, 1), (2, 0), (2, 1)]

    Here we compute the sum of each element of the multi-range iterator:
        sage: list(xmrange([3,2], sum))
        [0, 1, 1, 2, 2, 3]

    Next we compute the product:
        sage: list(xmrange([3,2], prod))
        [0, 0, 0, 1, 0, 2]
        
    Examples that illustrate empty multi-ranges. 
        sage: list(xmrange([]))
        []
        sage: list(xmrange([5,3,-2]))
        []
        sage: list(xmrange([5,3,0]))
        []

    We use a multi-range iterator to iterate through the cartesian
    product of sets.
        sage: X = ['red', 'apple', 389]
        sage: Y = ['orange', 'horse']
        sage: for i,j in xmrange([len(X), len(Y)]):
        ...    print (X[i], Y[j])
        ('red', 'orange')
        ('red', 'horse')
        ('apple', 'orange')
        ('apple', 'horse')
        (389, 'orange')
        (389, 'horse')
               
    AUTHORS:
        -- Jon Hanke
        -- William Stein
    """
    def __init__(self, sizes, typ=list):
        self.sizes = [int(x) for x in sizes]
        self.typ = typ

    def __repr__(self):
        if self.typ == list:
            return 'xmrange(%s)'%self.sizes
        else:
            return 'xmrange(%s, %s)'%(self.sizes, self.typ)

    def __len__(self):
        sizes = self.sizes
        n = len(sizes)
        if n == 0:
            return 0
        for i in sizes:
            if i <= 0:
                return 0
        return misc.prod(sizes, 1)
        
    def __iter__(self):
        return _xmrange(self.sizes, self.typ)

def cartesian_product_iterator(X):
    """
    Iterate over the Cartesian product.
    
    INPUT:
        X -- list or tuple of lists
    OUTPUT:
        iterator over the cartesian product of the elements of X

    EXAMPLES:
        sage: list(cartesian_product_iterator([[1,2], ['a','b']]))
        [(1, 'a'), (1, 'b'), (2, 'a'), (2, 'b')]    
    """
    return xmrange_iter(X, tuple)

"""
k-Schur Functions
"""
#*****************************************************************************
#       Copyright (C) 2011 Jason Bandlow <jbandlow@gmail.com>, 
#                     2012 Anne Schilling <anne@math.ucdavis.edu>
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
#*****************************************************************************
from sage.rings.all import Integer
from sage.structure.unique_representation import UniqueRepresentation
from sage.structure.parent import Parent
from sage.categories.realizations import Realizations, Category_realization_of_parent
from sage.categories.graded_hopf_algebras import GradedHopfAlgebras
from sage.categories.graded_hopf_algebras_with_basis import GradedHopfAlgebrasWithBasis
from sage.categories.graded_coalgebras import GradedCoalgebras
from sage.categories.graded_coalgebras_with_basis import GradedCoalgebrasWithBasis 
from sage.categories.magmas import Magmas
from sage.categories.examples.infinite_enumerated_sets import NonNegativeIntegers
from sage.categories.tensor import tensor
from sage.combinat.partition import Partition, Partitions, Partition_class
from sage.combinat.sf.sf import SymmetricFunctions
from sage.categories.morphism import SetMorphism
from sage.categories.sets_with_partial_maps import SetsWithPartialMaps
from sage.categories.homset import Hom
from sage.misc.cachefunc import cached_method
from sage.combinat.free_module import CombinatorialFreeModule
from sage.misc.constant_function import ConstantFunction
from sage.matrix.constructor import matrix
from sage.misc.misc import srange

class KBoundedSubspace(UniqueRepresentation, Parent):
    r"""
    This class implements the subspace of the ring of symmetric functions spanned by
    `\{ s_{\lambda}[X/(1-t)] \}_{\lambda_1\le k} = \{ s_{\lambda}^{(k)}[X,t]\}_{\lambda_1 \le k}`
    over the base ring `\mathbb{Q}[t]`. When `t=1`, this space is in fact a subring of
    the ring of symmetric functions generated by the complete homogeneous symmetric functions
    `h_i` for `1\le i \le k`.

    EXAMPLES::

        sage: Sym = SymmetricFunctions(QQ)
        sage: KB = Sym.kBoundedSubspace(3,1); KB
        3-bounded Symmetric Functions over Rational Field with t=1

        sage: Sym = SymmetricFunctions(QQ['t'])
        sage: KB = Sym.kBoundedSubspace(3); KB
        3-bounded Symmetric Functions over Univariate Polynomial Ring in t over Rational Field

    The `k`-Schur function basis can be constructed as follows::

        sage: ks = KB.kschur(); ks
        3-bounded Symmetric Functions over Univariate Polynomial Ring in t over Rational Field in the 3-Schur basis
    """
    
    def __init__(self, Sym, k, t='t'):
        r"""
        The class modeling the abstract vector space of `k`-Schur functions; if `t=1` this 
        is actually an abstract ring. Another way to describe this space is as the subspace of 
        a ring of symmetric functions generated by the complete homogeneous symmetric functions
        `h_i` for `1\le i \le k`.

        TESTS::

            sage: Sym = SymmetricFunctions(QQ)
            sage: from sage.combinat.sf.new_kschur import KBoundedSubspace
            sage: L3 = KBoundedSubspace(Sym,3,1)
            sage: TestSuite(L3).run(skip=["_test_not_implemented_methods"])
            sage: Sym.kBoundedSubspace(0,1)
            Traceback (most recent call last):
            ...
            ValueError: k must be a positive integer

            sage: Sym = SymmetricFunctions(QQ['t'])
            sage: TestSuite(Sym.kBoundedSubspace(1)).run(skip=["_test_not_implemented_methods"])
        """
        if not isinstance(k, (int, Integer)) or (k < 1):
            raise ValueError, "k must be a positive integer"

        if not isinstance(Sym,SymmetricFunctions):
            raise ValueError, "Sym must be an algebra of symmetric functions"
        
        self.indices = ConstantFunction(Partitions(NonNegativeIntegers(), max_part=k))

        R = Sym.base_ring()

        # The following line is a work around for the fact that Parent defines
        # self.base_ring as NotImplemented, hence it cannot be defined by the
        # category framework.
        self.base_ring = ConstantFunction(R)
        
        self.ambient = ConstantFunction(Sym)

        self.k = k
        self.t = R(t)

        category = GradedHopfAlgebras(R) if t == 1 else GradedCoalgebras(R)
        Parent.__init__(self, category = category.Subobjects().WithRealizations())

        ks = self.kschur()
        # Coercions
        if t == 1:
            s = ks.ambient()
            kh = self.khomogeneous(); h = kh.ambient()
            h_to_s   = s.coerce_map_from(h)
            kh_to_ks = ks.retract * h_to_s * kh.lift
            ks.register_coercion(kh_to_ks)
            s_to_h   = h.coerce_map_from(s)
            ks_to_kh = kh.retract * s_to_h * ks.lift
            kh.register_coercion(ks_to_kh)
        # temporary workaround until handled by trac 125959
            self.one = ConstantFunction(ks.one())
        self.zero = ConstantFunction(ks.zero())


    def retract(self, sym):
        r"""
        Retracts ``sym`` from ``self`` to the ring of symmetric functions.

        INPUT: 

        - ``sym`` -- a symmetric function

        OUTPUT: 

        - the analogue of the symmetric function in the `k`-bounded subspace (if possible)

        EXAMPLES::

            sage: Sym = SymmetricFunctions(QQ)
            sage: s = Sym.schur()
            sage: KB = Sym.kBoundedSubspace(3,1); KB
            3-bounded Symmetric Functions over Rational Field with t=1
            sage: KB.retract(s[2]+s[3])
            ks3[2] + ks3[3]
            sage: KB.retract(s[2,1,1])
            Traceback (most recent call last):
            ...
            ValueError: s[2, 1, 1] is not in the image of Generic morphism:
              From: 3-bounded Symmetric Functions over Rational Field with t=1 in the 3-Schur basis also with t=1
              To:   Symmetric Functions over Rational Field in the Schur basis
        """
        s = self.ambient().schur()
        ks = self.kschur()
        return ks.retract(s(sym))

    def realizations(self):
        r"""
        A list of realizations of this algebra.

        EXAMPLES::

            sage: SymmetricFunctions(QQ).kBoundedSubspace(3,1).realizations()
            [3-bounded Symmetric Functions over Rational Field with t=1 in the 3-Schur basis also with t=1, 3-bounded Symmetric Functions over Rational Field with t=1 in the 3-bounded homogeneous basis]

            sage: SymmetricFunctions(QQ['t']).kBoundedSubspace(3).realizations()
            [3-bounded Symmetric Functions over Univariate Polynomial Ring in t over Rational Field in the 3-Schur basis]
        """
        if self.t == 1:
            return [self.kschur(), self.khomogeneous()]
        else:
            return [self.kschur()]
        
    def kschur(self):
        r"""
        The `k`-Schur basis of this algebra.

        .. SEEALSO:: :meth:`kSchur` 

        EXAMPLES::

            sage: ks3 = SymmetricFunctions(QQ).kBoundedSubspace(3,1).kschur()
            sage: TestSuite(ks3).run()
        """
        return kSchur(self)

    def khomogeneous(self):
        r"""
        The homogeneous basis of this algebra.

        .. SEEALSO:: :meth:`kHomogeneous`

        EXAMPLES::

            sage: kh3 = SymmetricFunctions(QQ).kBoundedSubspace(3,1).khomogeneous()
            sage: TestSuite(kh3).run()
        """
        assert self.t == 1, "This basis only exists for t=1"
        return kHomogeneous(self)

    def _repr_(self):
        r"""
        Representation of this algebra.

        EXAMPLES::

            sage: SymmetricFunctions(QQ).kBoundedSubspace(3,1) # indirect doctest
            3-bounded Symmetric Functions over Rational Field with t=1

            sage: SymmetricFunctions(QQ['t']).kBoundedSubspace(3)
            3-bounded Symmetric Functions over Univariate Polynomial Ring in t over Rational Field
        """
        ending = ""
        if str(self.t)!='t':
            ending = ' with t=%s'%(self.t)
        return "%s-bounded %s"%(self.k, self.ambient())+ending


class KBoundedSubspaceBases(Category_realization_of_parent):
    r"""
    The category of bases for the `k`-bounded subspace of symmetric functions.
    """

    def __init__(self, base, t='t'):
        """
        Initialization of the bases of the `k`-bounded subspace

        INPUT:

        - ``base`` -- a basis in the `k`-bounded subspace
        - ``t` -- a parameter (default: 't')

        TESTS::

            sage: Sym = SymmetricFunctions(QQ['t'])
            sage: from sage.combinat.sf.new_kschur import KBoundedSubspaceBases
            sage: KB = Sym.kBoundedSubspace(3)
            sage: ks = KB.kschur()
            sage: KBB = KBoundedSubspaceBases(ks); KBB
            Category of k bounded subspace bases of 3-bounded Symmetric Functions over Univariate Polynomial Ring in t over Rational Field in the 3-Schur basis
        """
        self.t = t
        Category_realization_of_parent.__init__(self, base)

    def super_categories(self):
        r"""
        The super categories of ``self``.

        EXAMPLES::

            sage: Sym = SymmetricFunctions(QQ['t'])
            sage: from sage.combinat.sf.new_kschur import KBoundedSubspaceBases
            sage: KB = Sym.kBoundedSubspace(3)
            sage: KBB = KBoundedSubspaceBases(KB); KBB
            Category of k bounded subspace bases of 3-bounded Symmetric Functions over Univariate Polynomial Ring in t over Rational Field
            sage: KBB.super_categories()
            [Category of realizations of 3-bounded Symmetric Functions over Univariate Polynomial Ring in t over Rational Field, Join of Category of graded coalgebras with basis over Univariate Polynomial Ring in t over Rational Field and Category of subobjects of sets]
        """
        R = self.base().base_ring()
        category = GradedHopfAlgebrasWithBasis(R) if self.t == 1 else GradedCoalgebrasWithBasis(R)
        return [Realizations(self.base()), category.Subobjects()]

    class ParentMethods:
        
        def _convert_map_from_(self,Q):
            r"""
            Implements conversion from an arbitrary parent to ``self``.

            This is done by first coercing to the appropriate lift basis.

            EXAMPLES::

                sage: Sym = SymmetricFunctions(QQ)
                sage: e = Sym.elementary(); ks3 = Sym.kschur(3,1)
                sage: ks3(e[3, 2])                   # indirect doctest
                ks3[1, 1, 1, 1, 1]
            """
            P = self.lift.codomain()
            if P.has_coerce_map_from(Q):
                return self.retract * P.coerce_map_from(Q)
            return None
       
        def __getitem__(self, c, *rest):
            r"""
            Implements shorthand for accessing basis elements.

            For a basis `X` indexed by partitions, this method allows for
            `X[[3,2]]` and `X[3,2]` to be equivalent to `X[Partition([3,2])]`.

            Due to limitations in Python syntax, one must use `X[[]]` and not
            `X[]` for the basis element indexed by the empty partition.

            EXAMPLES::

                sage: ks3 = SymmetricFunctions(QQ).kschur(3,1)
                sage: ks3[3,2]
                ks3[3, 2]
                sage: ks3[[]]
                ks3[]
            """
            if isinstance(c, Partition_class):
                assert len(rest) == 0
            else:
                if len(rest) > 0 or isinstance(c,(int,Integer)):
                    c = Partition([c]+list(rest))
                else:
                    c = Partition(list(c))
            return self.monomial(c)

        def _repr_term(self, c):
            """
            Display elements with single brackets.

            The default implementation of CombinatorialFreeModule gives double
            brackets for basis elements indexed by partitions, i.e.,
            `X[[3,2]]`.

            EXAMPLES::
            
                sage: ks3 = SymmetricFunctions(QQ).kschur(3,1)
                sage: ks3[3,2]    # indirect doctest
                ks3[3, 2]
            """
            return self.prefix()+str(c)

        @cached_method
        def one_basis(self):
            r"""
            Return the basis element indexing ``1``.

            EXAMPLES::

                sage: ks3 = SymmetricFunctions(QQ).kschur(3,1)
                sage: ks3.one()  # indirect doctest
                ks3[]
            """
            return Partition([])

        def transition_matrix(self, other, n):
            """
            Return the degree ``n`` transition matrix between ``self`` and ``other``.

            INPUT:

            - ``other`` -- a basis in the ring of symmetric functions
            - ``n`` -- a positive integer

            The entry in the `i^{th}` row and `j^{th}` column is the
            coefficient obtained by writing the `i^{th}` element of the
            basis of ``self`` in terms of the basis ``other``, and extracting the
            `j^{th}` coefficient.
            
            EXAMPLES::

                sage: Sym = SymmetricFunctions(QQ); s = Sym.schur()
                sage: ks3 = Sym.kschur(3,1)
                sage: ks3.transition_matrix(s,5)
                [1 1 1 0 0 0 0]
                [0 1 0 1 0 0 0]
                [0 0 1 0 1 0 0]
                [0 0 0 1 0 1 0]
                [0 0 0 0 1 1 1]

                sage: Sym = SymmetricFunctions(QQ['t'])
                sage: s = Sym.schur()
                sage: ks = Sym.kschur(3)
                sage: ks.transition_matrix(s,5)
                [t^2   t   1   0   0   0   0]
                [  0   t   0   1   0   0   0]
                [  0   0   t   0   1   0   0]
                [  0   0   0   t   0   1   0]
                [  0   0   0   0 t^2   t   1]
            """
            P = Partitions(n, max_part=self.k)
            # todo: Q should be set by getting the degree n index set for
            # `other`.
            Q = Partitions(n)
            return matrix( [[other(self[row]).coefficient(col) for col in Q]
                            for row in P] )

        def an_element(self):
            r"""
            Return an element of ``self``.

            EXAMPLES::
                
                sage: SymmetricFunctions(QQ['t']).kschur(3).an_element()
                ks3[] + 2*ks3[1] + 3*ks3[2]
            """    
            return self( Partition(srange(self.k,0,-1)))

        # This is sufficient for degree to work
        def degree_on_basis(self, b):
            r"""
            Return the degree of the basis element indexed by `b`.

            INPUT:
            - ``b`` -- a partition

            EXAMPLES::

                sage: ks3 = SymmetricFunctions(QQ).kschur(3,1)
                sage: ks3.degree_on_basis(Partition([3,2]))
                5
            """
            return sum(b)


    class ElementMethods:

        __mul__ = Magmas.ElementMethods.__mul__.im_func

        def _mul_(self, other):
            r"""
            Method for multiplying two elements.

            When `t=1`, the `k`-bounded subspace is an algebra, so the product of two elements
            is always in the space. For generic `t`, the `k`-bounded subspace is not closed under
            multiplication, so the result is returned in the `k`-bounded subspace if possible and
            else in the ring of symmetric functions.

            EXAMPLES::

                sage: Sym = SymmetricFunctions(QQ['t'])
                sage: ks = Sym.kschur(3)
                sage: ks[2]*ks[2]                        # indirect doctest
                s[2, 2] + s[3, 1] + s[4]
                sage: f = ks[2]*ks[3,1]; f
                s[3, 2, 1] + s[3, 3] + s[4, 1, 1] + (t+1)*s[4, 2] + (t+1)*s[5, 1] + t*s[6]
                sage: f.parent()
                Symmetric Functions over Univariate Polynomial Ring in t over Rational Field in the Schur basis
                sage: ks(f)
                Traceback (most recent call last):
                ...
                ValueError: s[3, 2, 1] + s[3, 3] + s[4, 1, 1] + (t+1)*s[4, 2] + (t+1)*s[5, 1] + t*s[6] is not in the image of Generic morphism:
                  From: 3-bounded Symmetric Functions over Univariate Polynomial Ring in t over Rational Field in the 3-Schur basis
                  To:   Symmetric Functions over Univariate Polynomial Ring in t over Rational Field in the Schur basis

                sage: Sym = SymmetricFunctions(QQ)
                sage: ks = Sym.kschur(3,1)
                sage: f = ks[2]*ks[3,1]; f
                ks3[3, 2, 1] + ks3[3, 3]
                sage: f.parent()
                3-bounded Symmetric Functions over Rational Field with t=1 in the 3-Schur basis also with t=1

            TESTS::

                sage: Sym = SymmetricFunctions(FractionField(QQ['t']))
                sage: ks2 = Sym.kschur(2)
                sage: ks3 = Sym.kschur(3)
                sage: ks5 = Sym.kschur(5)
                sage: ks5(ks3[2]) * ks5(ks2[2,1])
                ks5[2, 2, 1] + ks5[3, 1, 1] + (t+1)*ks5[3, 2] + (t+1)*ks5[4, 1] + t*ks5[5]
            """
            if self.parent().realization_of().t == 1:
                return self.parent()(self.lift()*other.lift())
            result = self.lift()*other.lift()
            try:
                result = self.parent()(result)
            except ValueError:
                pass
            return result

        def hl_creation_operator(self, nu, t = None):
            r"""
            This is the vertex operator that generalizes Jing's operator.

            It is a linear operator that raises the degree by
            `|\nu|`. This creation operator is a t-analogue of
            multiplication by ``s(nu)`` .

            .. SEEALSO:: Proposition 5 in [SZ.2001]_.

            INPUT:

            -  ``nu`` -- a partition

            - ``t`` -- a parameter (default: None, in this case `t` is used)

            REFERENCES:

            .. [SZ.2001] M. Shimozono, M. Zabrocki,
               Hall-Littlewood vertex operators and generalized Kostka polynomials.
               Adv. Math. 158 (2001), no. 1, 66-85.

            EXAMPLES::

                sage: Sym = SymmetricFunctions(FractionField(QQ['t']))
                sage: ks = Sym.kschur(4)
                sage: s = Sym.schur()
                sage: s(ks([3,1,1]).hl_creation_operator([1]))
                (t-1)*s[2, 2, 1, 1] + t^2*s[3, 1, 1, 1] + (t^3+t^2-t)*s[3, 2, 1] + (t^3-t^2)*s[3, 3] + (t^4+t^3)*s[4, 1, 1] + t^4*s[4, 2] + t^5*s[5, 1]
                sage: ks([3,1,1]).hl_creation_operator([1])
                (t-1)*ks4[2, 2, 1, 1] + t^2*ks4[3, 1, 1, 1] + t^3*ks4[3, 2, 1] + (t^3-t^2)*ks4[3, 3] + t^4*ks4[4, 1, 1]

                sage: Sym = SymmetricFunctions(QQ)
                sage: ks = Sym.kschur(4,t=1)
                sage: ks([3,1,1]).hl_creation_operator([1])
                ks4[3, 1, 1, 1] + ks4[3, 2, 1] + ks4[4, 1, 1]
            """
            if t is None:
                t = self.parent().realization_of().t
            return self.parent()(self.lift().hl_creation_operator(nu,t=t))

        def coproduct(self):
            r"""
            Returns the coproduct operation on ``self``.

            The coproduct is first computed on the homogeneous basis if `t=1` and
            on the Hall-Littlewood ``Qp`` basis otherwise.  The result is computed
            then converted to the tensor squared of ``self.parent()``

            EXAMPLES::

                sage: Sym = SymmetricFunctions(QQ)
                sage: ks3 = Sym.kschur(3,1)
                sage: ks3[2,1].coproduct()
                ks3[] # ks3[2, 1] + ks3[1] # ks3[1, 1] + ks3[1] # ks3[2] + ks3[1, 1] # ks3[1] + ks3[2] # ks3[1] + ks3[2, 1] # ks3[]
                sage: h3 = Sym.khomogeneous(3)
                sage: h3[2,1].coproduct()
                h3[] # h3[2, 1] + h3[1] # h3[1, 1] + h3[1] # h3[2] + h3[1, 1] # h3[1] + h3[2] # h3[1] + h3[2, 1] # h3[]
                sage: ks3t = SymmetricFunctions(FractionField(QQ['t'])).kschur(3)
                sage: ks3t[2,1].coproduct()
                ks3[] # ks3[2, 1] + ks3[1] # ks3[1, 1] + ks3[1] # ks3[2] + ks3[1, 1] # ks3[1] + ks3[2] # ks3[1] + ks3[2, 1] # ks3[]
                sage: ks3t[3,1].coproduct()
                ks3[] # ks3[3, 1] + ks3[1] # ks3[2, 1] + (t+1)*ks3[1] # ks3[3] + ks3[1, 1] # ks3[2] + ks3[2] # ks3[1, 1] 
                + (t+1)*ks3[2] # ks3[2] + ks3[2, 1] # ks3[1] + (t+1)*ks3[3] # ks3[1] + ks3[3, 1] # ks3[]
            """
            lifted = self.lift()
            target_basis = self.parent()
            ambient = self.parent().realization_of().ambient()
            t = self.parent().realization_of().t
            if t==1:
                source_basis = ambient.h()
            else:
                source_basis = ambient.hall_littlewood(t=t).Qp()
            cpfunc = lambda x,y: tensor([ target_basis(x), target_basis(y) ])
            return source_basis(lifted).coproduct().apply_multilinear_morphism( cpfunc )


        def omega(self):
            r"""
            Returns the `\omega` operator on ``self``.
            
            At `t=1`, `\omega` maps the `k`-Schur function `s^{(k)}_\lambda` to `s^{(k)}_{\lambda^{(k)}}`, where
            `\lambda^{(k)}` is the `k`-conjugate of the partition `\lambda`.

            .. SEEALSO:: :meth:`~sage.combinat.partition.Partition_class.k_conjugate`.

            For generic `t`, `\omega` sends `s^{(k)}_\lambda[X;t]` to `t^d s^{(k)}_{\lambda^{(k)}}[X;1/t]`,
            where `d` is the size of the core of `\lambda` minus the size of `\lambda`. Most of the time,
            this result is not in the `k`-bounded subspace.

            .. SEEALSO:: :meth:`omega_t_inverse`.
            
            EXAMPLES::

                sage: Sym = SymmetricFunctions(QQ)
                sage: ks = Sym.kschur(3,1)
                sage: ks[2,2,1,1].omega()
                ks3[2, 2, 2]
                sage: kh = Sym.khomogeneous(3)
                sage: kh[3].omega()
                h3[1, 1, 1] - 2*h3[2, 1] + h3[3]

                sage: Sym = SymmetricFunctions(FractionField(QQ['t']))
                sage: ks = Sym.kschur(3)
                sage: ks[3,1,1].omega()
                Traceback (most recent call last):
                ...
                ValueError: t*s[2, 1, 1, 1] + s[3, 1, 1] is not in the image of Generic morphism:
                From: 3-bounded Symmetric Functions over Fraction Field of Univariate Polynomial Ring in t over Rational Field in the 3-Schur basis
                To:   Symmetric Functions over Fraction Field of Univariate Polynomial Ring in t over Rational Field in the Schur basis
            """
            return self.parent()(self.lift().omega())

        def omega_t_inverse(self):
            r"""
            Returns the map `t\to 1/t` composed with `\omega` on ``self``.

            Unlike the map :meth:`omega`, the result of :meth:`omega_t_inverse` lives in the
            `k`-bounded subspace and hence will return an element even for generic `t`. For `t=1`,
            :meth:`omega` and :meth:`omega_t_inverse` return the same result.

            EXAMPLES::

                sage: Sym = SymmetricFunctions(FractionField(QQ['t']))
                sage: ks = Sym.kschur(3)
                sage: ks[3,1,1].omega_t_inverse()
                1/t*ks3[2, 1, 1, 1]
                sage: ks[3,2].omega_t_inverse()
                1/t^2*ks3[1, 1, 1, 1, 1]
            """
            s = self.parent().realization_of().ambient()
            t = s.base_ring().gen()
            invert = lambda x: s.base_ring()(x.subs(t=1/t))
            return self.parent()(s(self).map_coefficients(invert).omega())

        def is_schur_positive(self, *args, **kwargs):
            r"""
            Returns whether ``self`` is Schur positive.

            EXAMPLES::

                sage: Sym = SymmetricFunctions(QQ)
                sage: ks = Sym.kschur(3,1)
                sage: f = ks[3,2]+ks[1]
                sage: f.is_schur_positive()
                True
                sage: f = ks[3,2]-ks[1]
                sage: f.is_schur_positive()
                False

                sage: Sym = SymmetricFunctions(QQ['t'])
                sage: ks = Sym.kschur(3)
                sage: f = ks[3,2]+ks[1]
                sage: f.is_schur_positive()
                True
                sage: f = ks[3,2]-ks[1]
                sage: f.is_schur_positive()
                False
            """
            return self.lift().is_schur_positive(*args,**kwargs)

        def expand(self, *args, **kwargs):
            r"""
            Returns the monomial expansion of ``self`` in `n` variables.

            INPUT: 

            - ``n`` -- positive integer

            OUTPUT: monomial expansion of ``self`` in `n` variables

            EXAMPLES::

                sage: Sym = SymmetricFunctions(QQ)
                sage: ks = Sym.kschur(3,1)
                sage: ks[3,1].expand(2)
                x0^4 + 2*x0^3*x1 + 2*x0^2*x1^2 + 2*x0*x1^3 + x1^4
                sage: s = Sym.schur()
                sage: ks[3,1].expand(2) == s(ks[3,1]).expand(2)
                True

                sage: Sym = SymmetricFunctions(QQ['t'])
                sage: ks = Sym.kschur(3)
                sage: f = ks[3,2]-ks[1]
                sage: f.expand(2)
                t^2*x0^5 + (t^2 + t)*x0^4*x1 + (t^2 + t + 1)*x0^3*x1^2 + (t^2 + t + 1)*x0^2*x1^3 + (t^2 + t)*x0*x1^4 + t^2*x1^5 - x0 - x1
            """
            return self.lift().expand(*args,**kwargs)

        
class kSchur(CombinatorialFreeModule):       

    def __init__(self, kBoundedRing):
        r"""
        TESTS::
 
            sage: Sym = SymmetricFunctions(QQ)
            sage: from sage.combinat.sf.new_kschur import kSchur
            sage: KB = Sym.kBoundedSubspace(3,t=1)
            sage: kSchur(KB)
            3-bounded Symmetric Functions over Rational Field with t=1 in the 3-Schur basis also with t=1
        """
        CombinatorialFreeModule.__init__(self, kBoundedRing.base_ring(),
            kBoundedRing.indices(),
            category= KBoundedSubspaceBases(kBoundedRing, kBoundedRing.t),
            prefix='ks%d'%kBoundedRing.k)

        self._kBoundedRing = kBoundedRing

        self.k = kBoundedRing.k

        s = self.realization_of().ambient().schur()

        self.ambient = ConstantFunction(s)
        
        self.lift = self._module_morphism(self._to_schur_on_basis,
                codomain=s, triangular='lower', unitriangular=True, 
                inverse_on_support=lambda p: p if p.get_part(0) <= self.k else None)

        self.lift.register_as_coercion()

        self.retract = SetMorphism(Hom(s, self, SetsWithPartialMaps()),
                self.lift.preimage)
        self.register_conversion(self.retract)

    # The following are meant to be inherited with the category framework, but
    # this fails because they are methods of Parent. The trick below overcomes
    # this problem.
    __getitem__ = KBoundedSubspaceBases.ParentMethods.__getitem__.im_func
    _repr_term = KBoundedSubspaceBases.ParentMethods._repr_term.im_func
    _convert_map_from_ = KBoundedSubspaceBases.ParentMethods._convert_map_from_.im_func

    def _repr_(self):
        """
        Representation of ``self``.

        EXAMPLES::

            sage: Sym = SymmetricFunctions(QQ)
            sage: ks = Sym.kschur(4,1); ks      # indirect doctest
            4-bounded Symmetric Functions over Rational Field with t=1 in the 4-Schur basis also with t=1

            sage: Sym = SymmetricFunctions(QQ['t'])
            sage: ks = Sym.kschur(4); ks
            4-bounded Symmetric Functions over Univariate Polynomial Ring in t over Rational Field in the 4-Schur basis
        """
        ending = ''
        if str(self.realization_of().t)!='t':
            ending = ' also with t=%s'%(self.realization_of().t)
        return self.realization_of()._repr_()+' in the %s-Schur basis'%(self.k)+ending

    @cached_method
    def _to_schur_on_basis(self, p):
        r"""
        Computes the change of basis from `k`-Schur functions to Schur functions.

        INPUT:

        - ``p`` -- a partition

        OUTPUT: conversion of the `k`-Schur function indexed by ``p`` in terms of Schur functions 
        
        EXAMPLES::

            sage: Sym = SymmetricFunctions(QQ['t'])
            sage: ks = Sym.kschur(4)
            sage: ks._to_schur_on_basis(Partition([3,3,2,1]))
            s[3, 3, 2, 1] + t*s[4, 3, 1, 1] + t*s[4, 3, 2] + t^2*s[4, 4, 1] + t^2*s[5, 3, 1] + t^3*s[5, 4]
        """
        katom = p.k_atom(self.k)
        s = self.realization_of().ambient().schur()
        t = self.realization_of().t
        if t == 1:
            return s.sum_of_monomials(tab.shape() for tab in katom)
        return s.sum_of_terms((tab.shape(), t**tab.charge()) for tab in katom)
     

class kHomogeneous(CombinatorialFreeModule):
    r"""
    Space of `k`-bounded homogeneous symmetric functions.

    EXAMPLES::

        sage: Sym = SymmetricFunctions(QQ)
        sage: kH = Sym.khomogeneous(3)
        sage: kH[2]
        h3[2]
        sage: kH[2].lift()
        h[2]
    """

    def __init__(self, kBoundedRing):
        r"""
        TESTS::

            sage: Sym = SymmetricFunctions(QQ)
            sage: from sage.combinat.sf.new_kschur import kHomogeneous
            sage: KB = Sym.kBoundedSubspace(3,t=1)
            sage: kHomogeneous(KB)
            3-bounded Symmetric Functions over Rational Field with t=1 in the 3-bounded homogeneous basis
        """
        CombinatorialFreeModule.__init__(self, kBoundedRing.base_ring(),
            kBoundedRing.indices(),
            category= KBoundedSubspaceBases(kBoundedRing, kBoundedRing.t),
            prefix='h%d'%kBoundedRing.k)

        self._kBoundedRing = kBoundedRing

        self.k = kBoundedRing.k

        h = self.realization_of().ambient().homogeneous()

        self.lift = self._module_morphism(lambda x: h[x],
                codomain=h, triangular='lower', unitriangular=True, 
                inverse_on_support=lambda p:p if p.get_part(0) <= self.k else None)

        self.ambient = ConstantFunction(h)  

        self.lift.register_as_coercion()

        self.retract = SetMorphism(Hom(h, self, SetsWithPartialMaps()),
                self.lift.preimage)
        self.register_conversion(self.retract)

    # The following are meant to be inherited with the category framework, but
    # this fails because they are methods of Parent. The trick below overcomes
    # this problem.
    __getitem__ = KBoundedSubspaceBases.ParentMethods.__getitem__.im_func
    _repr_term = KBoundedSubspaceBases.ParentMethods._repr_term.im_func
    _convert_map_from_ =\
            KBoundedSubspaceBases.ParentMethods._convert_map_from_.im_func

    def _repr_(self):
        """
        TESTS::

            sage: Sym = SymmetricFunctions(QQ)
            sage: kH = Sym.khomogeneous(3)
            sage: kH._repr_()
            '3-bounded Symmetric Functions over Rational Field with t=1 in the 3-bounded homogeneous basis'
        """
        return self.realization_of()._repr_()+' in the %s-bounded homogeneous basis'%(self.k)

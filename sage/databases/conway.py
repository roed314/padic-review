"""
Frank Luebeck's tables of Conway polynomials over finite fields
"""


## On 3/29/07, David Joyner <wdjoyner@gmail.com> wrote:
## > I guessed what you would do to create the *.bz2 file
## > and I think it turned out to be right. (You did things the simplest way,
## > as far as I can see.) The file is posted at
## > http://sage.math.washington.edu/home/wdj/patches/conway_table.py.bz2
## > I think what you did was (a) take the data file from
## > http://www.math.rwth-aachen.de/~Frank.Luebeck/data/ConwayPol/CPimport.txt
## > (b) renamed the file conway_table.py
## > (c) used an editor to make a few changes to the first few and last
## > few lines of the data file,
## > (d) packed it using bzip2.
## >
## > I did this and placed the *bz2 file in the correct directory
## > (as determined by conway.py). Here's a test
## >
## > sage: R = PolynomialRing(GF(2),"x")
## > sage: R(ConwayPolynomials()[2][3])
## > x^3 + x + 1
## >
## > If I am reading conway.py correctly then this test shows that the
## > file I created is what you want.
## >
## > If you agree, then I will add the new data (you forwarded by
## > separate emails) to it.
## >
## > Please let me know if this is reasonable.

## Yes, you did exactly the right thing, which I verified as follows:

## (1) delete SAGE_SHARE/conway_polynomials/*
## (2) put your conway_polynomial.py.bz2 file in a new directory
##      /home/was/s/data/src/conway/
## (3) Start Sage:
## sage: c = ConwayPolynomials(read_only=False)
## sage: c._init()       # builds database
## sage: c.polynomial(3,10)
## [2, 1, 0, 0, 2, 2, 2, 0, 0, 0, 1]
## (4) restart and test:
## sage: conway_polynomial(3,10)
## x^10 + 2*x^6 + 2*x^5 + 2*x^4 + x + 2


#*****************************************************************************
#       
#       Sage: Copyright (C) 2005 William Stein <wstein@gmail.com>
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

import os

import sage.databases.db   # very important that this be fully qualified
_CONWAYDATA = os.path.join(sage.misc.misc.SAGE_SHARE,'conway_polynomials')


class ConwayPolynomials(sage.databases.db.Database):
    def __init__(self, read_only=True):
        """
        Initialize the database.
        
        INPUT:
        
        -  ``read_only`` - bool (default: True), if True, then
           the database is read_only and changes cannot be committed to
           disk.

        TESTS::

            sage: c = ConwayPolynomials()
            sage: c
            Frank Luebeck's database of Conway polynomials
            sage: c.read_only
            True
        """
        sage.databases.db.Database.__init__(self,
             name="conway_polynomials", read_only=read_only)

    def _init(self):
        if not os.path.exists(_CONWAYDATA):
            raise RuntimeError, "In order to initialize the database, the directory must exist."%_CONWAYDATA
        os.chdir(_CONWAYDATA)
        if os.system("bunzip2 -k conway_table.py.bz2"):
            raise RuntimeError, "error decompressing table"
        from conway_table import conway_polynomials
        for X in conway_polynomials:
            (p, n, v) = tuple(X)
            if not self.has_key(p):
                self[p] = {}
            self[p][n] = v
            self[p] = self[p]  # so database knows it was changed
        os.unlink("conway_table.pyc")
        os.unlink("conway_table.py")
        self.commit()

    def __repr__(self):
        """
        Return a description of this database.

        TESTS:

            sage: c = ConwayPolynomials()
            sage: c.__repr__()
            "Frank Luebeck's database of Conway polynomials"
        """
        return "Frank Luebeck's database of Conway polynomials"


    def polynomial(self, p, n):
        """
        Return the Conway polynomial of degree ``n`` over ``GF(p)``,
        or raise a RuntimeError if this polynomial is not in the
        database.

        .. NOTE::

            See also the global function ``conway_polynomial`` for
            a more user-friendly way of accessing the polynomial.

        INPUT:

        - ``p`` -- prime number

        - ``n`` -- positive integer

        OUTPUT:

        List of Python int's giving the coefficients of the corresponding
        Conway polynomial in ascending order of degree.

        EXAMPLES::

            sage: c = ConwayPolynomials()
            sage: c.polynomial(3, 21)
            [1, 2, 0, 2, 0, 1, 2, 0, 2, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]
            sage: c.polynomial(97, 128)
            Traceback (most recent call last):
            ...
            RuntimeError: Conway polynomial over F_97 of degree 128 not in database.
        """
        try:
            return self[int(p)][int(n)]
        except KeyError:
            raise RuntimeError, "Conway polynomial over F_%s of degree %s not in database."%(p,n)

    def has_polynomial(self, p, n):
        """
        Return True if the database of Conway polynomials contains the
        polynomial of degree ``n`` over ``GF(p)``.

        INPUT:

        - ``p`` -- prime number

        - ``n`` -- positive integer

        EXAMPLES::

            sage: c = ConwayPolynomials()
            sage: c.has_polynomial(97, 12)
            True
            sage: c.has_polynomial(60821, 5)
            False
        """
        return self.has_key(int(p)) and self[int(p)].has_key(int(n))

    def primes(self):
        """
        Return the list of prime numbers ``p`` for which the database of
        Conway polynomials contains polynomials over ``GF(p)``.

        EXAMPLES::

            sage: c = ConwayPolynomials()
            sage: P = c.primes()
            sage: 2 in P
            True
            sage: next_prime(10^7) in P
            False
        """
        return list(self.keys())

    def degrees(self, p):
        """
        Return the list of integers ``n`` for which the database of Conway
        polynomials contains the polynomial of degree ``n`` over ``GF(p)``.

        EXAMPLES::

            sage: c = ConwayPolynomials()
            sage: c.degrees(60821)
            [1, 2, 3, 4]
            sage: c.degrees(next_prime(10^7))
            []
        """
        p = int(p)
        if not p in self.primes():
            return []
        return self[p].keys()
        


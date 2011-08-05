"""Python wrapper for material library."""
# Cython imports
from libcpp.map cimport map as cpp_map
from libcpp.set cimport set as cpp_set
#from cython.operator cimport reference as ref
from cython.operator cimport dereference as deref
from cython.operator cimport preincrement as inc
from libc.stdlib cimport malloc, free


# local imports 
cimport std
cimport cpp_material
cimport pyne.stlconverters as conv
import pyne.stlconverters as conv

cimport pyne.nucname as nucname
import pyne.nucname as nucname
import os



cdef class Material:
    """Material composed of nuclides.

    Parameters
    ----------
    comp : dict or str 
        This is the input nuclide component dictionary.
        This dictionary need not be normalized; Material initialization will
        automatically renormalize the stream.  Thus the comp simply is a dictionary
        of relative weights.  The keys of comp must be integers representing
        nuclides in zzaaam-form.  The values are floats for each nuclide's weight 
        fraction. If a string is provided instead of a dictionary, then Material will
        read in the comp vector from a file at the string's location.  This  
        either plaintext or hdf5 files. If no comp is provided, an empty Material 
        object is constructed.
    mass : float, optional
        This is the mass of the new stream. If the mass provided
        is negative (default -1.0) then the mass of the new stream is calculated from 
        the sum of compdict's components before normalization.  If the mass here
        is positive or zero, then this mass overrides the calculated one.
    name : str, optional
        A string label for the material.  Helpful for large numbers of 
        streams. Default ''.

    """

    def __cinit__(self, nucvec=None, float mass=-1.0, char * name=''):
        """Material C++ constuctor."""
        cdef cpp_map[int, double] comp

        if isinstance(nucvec, dict):
            # Material from dict
            comp = conv.dict_to_map_int_dbl(nucvec)
            self.mat_pointer = new cpp_material.Material(comp, mass, std.string(name))

        elif isinstance(nucvec, basestring):
            # Material from file
            self.mat_pointer = new cpp_material.Material(<char *> nucvec, mass, std.string(name))

        elif nucvec is None:
            # Empty mass stream
            self.mat_pointer = new cpp_material.Material()

        else:
            # Bad Material 
            raise TypeError("The mass stream nucvec must be a dict, str, or None.")


    def __dealloc__(self):
        """Material C++ destructor."""
        del self.mat_pointer


    #
    # Class Attributes
    #

    property comp:
        def __get__(self):
            cdef conv._MapProxyIntDouble comp_proxy = conv.MapProxyIntDouble()
            comp_proxy.map_ptr = new cpp_map[int, double](self.mat_pointer.comp)
            return comp_proxy

        def __set__(self, dict comp):
            self.mat_pointer.comp = conv.dict_to_map_int_dbl(comp)


    property mass:
        def __get__(self):
            return self.mat_pointer.mass

        def __set__(self, double mass):
            self.mat_pointer.mass = mass


    property name:
        def __get__(self):
            cdef std.string mat_name = self.mat_pointer.name
            return mat_name.c_str()

        def __set__(self, char * name):
            self.mat_pointer.name = std.string(name)

    #
    # Class Methods
    #

    def norm_comp(self):
        """Normalizes the composition, preserving the mass of the nuclide vector as mass."""
        self.mat_pointer.norm_comp()


    def load_from_hdf5(self, char * filename, char * groupname, int row=-1):
        """Initialize a Material object from an HDF5 file.

        Parameters
        ----------
        filename : str
            Path to HDF5 file that contains the data to read in.    
        groupname : str 
            Path to HDF5 group that represents the data. 
            In the above example, groupname = "/Material".    
        row : int, optional 
            The index of the arrays from which to read the data.  This 
            ranges from 0 to N-1.  Defaults to the last element of the array.
            Negative indexing is allowed (row[-N] = row[0]).

        Notes
        -----
        The HDF5 representation of a Material is a group that holds several 
        extendable array datasets.  One array is entitled "Mass" while the other datasets
        are nuclide names in LLAAAM form ("U235", "NP237", *etc*).  For example::

            File.h5 (file)
                |-- Material (group)
                    |-- Mass (array)
                    |-- H1 (array)
                    |-- O16 (array)
                    |-- U235 (array)
                    |-- PU239 (array)
                    |-- ...

        The arrays are all of length N, where each row typically represents a different 
        fuel cycle pass.  The sum of all of the nuclide arrays should sum to one, like 
        Material.comp. 

        Examples
        --------
        This method loads data into a pre-existing :class:`Material`.  
        Initialization is therefore a two-step process::

            mat = Material()
            mat.load_from_hdf5("afile.h5", "/foo/bar/ms", -3)
        """
        self.mat_pointer.load_from_hdf5(filename, groupname, row)


    def load_from_text(self, char * filename):
        """Initialize a Material object from a simple text file.

        Parameters
        ----------
        filename : str 
            Path to HDF5 file that contains the data to read in.    


        Notes
        -----
        The text representation of Materials are nuclide identifiers in the 
        first column and mass or weight values in the second column.  For example, 
        for natural uranium::

            922340  0.000055
            U235    0.00720
            92238   0.992745

        Data in this file must be whitespace separated.  Any valid nuclide naming
        scheme may be used for any nuctope.

        Examples:
        ---------
        This method loads data into a pre-existing Material.  
        Initialization is therefore a two-step process::

            mat = Material()
            mat.load_from_text("natu.h5")

        This method is most often called implicitly by the Material constructor.
        """
        self.mat_pointer.load_from_text(filename)



    def normalize(self):
        """This convenience method normalizes the mass stream by setting its mass = 1.0."""
        self.mat_pointer.normalize()


    def mult_by_mass(self):
        """This multiplies multiplies comp by mass and returns the resultant nuctopic vector.

        Returns
        -------
        nucvec : dict
            For a Material mat, 

            .. math:: \\mbox{nucvec[nuc]} = \\mbox{mat.comp[nuc]} \\times \\mbox{mat.mass}
        """
        cdef conv._MapProxyIntDouble nucvec_proxy = conv.MapProxyIntDouble()
        nucvec_proxy.map_ptr = new cpp_map[int, double](self.mat_pointer.mult_by_mass())
        return nucvec_proxy


    def atomic_weight(self):
        """This method returns the atomic weight of the comp of this material.  Note that this is 
        only a rough estimate since this function is not yet coupled with measured atomic weights.

        Returns
        -------
        atomic_weight : float 
            Atomic weight in [amu]."""
        return self.mat_pointer.atomic_weight()


    #
    # submaterial Methods
    #

    def sub_mat(self, nuc_sequence, char * name=""):
        """Grabs a subset of the material and returns a new material comprised of only
        the specified nuclides.  

        Parameters
        ----------
        nuc_sequence : sequence
            Elements and nuctopes to be taken from current stream.
            Members of this list must be integers.  For example, [92, 942390]
            would take all uranium atoms and Pu-239.  
        name : str, optional
            The name of the submaterial.

        Returns
        -------
        submaterial : Material
            A new mass stream object that only 
            has the members given in nuc_sequence.  The mass of the submaterial
            is calculated based on the weight fraction composition and mass
            of the original mass stream.

        Notes
        -----
        The input here is seen as a suggestion and so no error is raised if a nuclide 
        is asked for via nuc_sequence that is not present in the original material.
        """
        # Make an nuctopic set 
        cdef int nuc_zz
        cdef cpp_set[int] nuc_set = cpp_set[int]()
        for nuc in nuc_sequence:
            if isinstance(nuc, int):
                if (nuc in nucname.zzLL):
                    nuc_zz = nuc
                else:
                    nuc_zz = nucname.zzaaam(nuc)

            elif isinstance(nuc, basestring):
                nuc_str = nuc.upper()
                if (nuc_str in nucname.LLzz):
                    nuc_zz = nucname.LLzz[nuc_str]
                else:
                    nuc_zz = nucname.zzaaam(nuc)

            else:
                raise TypeError("nuclides must be strings or integers.")

            nuc_set.insert(nuc_zz)

        # Make new python version of this mass stream
        pymat = Material()
        pymat.mat_pointer[0] = self.mat_pointer.sub_mat(nuc_set, std.string(name))
        return pymat


    def sub_u(self, char * name=""):
        """Convenience method that gets the Uranium portion of a mass stream.

        Parameters
        ----------
        name : str, optional 
            The name of the submaterial.

        Returns
        -------
        submaterial : Material 
            A new mass stream object that only has Uranium members. 
        """
        pymat = Material()
        pymat.mat_pointer[0] = self.mat_pointer.sub_u(std.string(name))
        return pymat
        

    def sub_pu(self, char * name=""):
        """Convenience method that gets the Plutonium portion of a mass stream.

        Parameters
        ----------
        name : str, optional 
            The name of the submaterial.

        Returns
        -------
        submaterial : Material 
            A new mass stream object that only has Plutonium members. 
        """
        pymat = Material()
        pymat.mat_pointer[0] = self.mat_pointer.sub_pu(std.string(name))
        return pymat
        

    def sub_lan(self, char * name=""):
        """Convenience method that gets the Lanthanide portion of a mass stream.

        Parameters
        ----------
        name : str, optional 
            The name of the submaterial.

        Returns
        -------
        submaterial : Material
            A new mass stream object that only has Lanthanide members. 
        """
        pymat = Material()
        pymat.mat_pointer[0] = self.mat_pointer.sub_lan(std.string(name))
        return pymat
        

    def sub_act(self, char * name=""):
        """Convenience method that gets the Actinide portion of a mass stream.

        Parameters
        ----------
        name : str, optional
            The name of the submaterial.

        Returns
        -------
        submaterial : Material
            A new mass stream object that only has Actinide members. 
        """
        pymat = Material()
        pymat.mat_pointer[0] = self.mat_pointer.sub_act(std.string(name))
        return pymat
        

    def sub_tru(self, char * name=""):
        """Convenience method that gets the Transuranic portion of a mass stream.

        Parameters
        ----------
        name : str, optional 
            The name of the submaterial.

        Returns
        -------
        submaterial : Material 
            A new mass stream object that only has Transuranic members. 
        """
        pymat = Material()
        pymat.mat_pointer[0] = self.mat_pointer.sub_tru(std.string(name))
        return pymat
        

    def sub_ma(self, char * name=""):
        """Convenience method that gets the Minor Actinide portion of a mass stream.

        Parameters
        ----------
        name : str, optional 
            The name of the submaterial.

        Returns
        -------
        submaterial : Material 
            A new mass stream object that only has Minor Actinide members. 
        """
        pymat = Material()
        pymat.mat_pointer[0] = self.mat_pointer.sub_ma(std.string(name))
        return pymat
        

    def sub_fp(self, char * name=""):
        """Convenience method that gets the Fission Product portion of a mass stream.

        Parameters
        ----------
        name : str, optional 
            The name of the submaterial.

        Returns
        -------
        submaterial : Material 
            A new mass stream object that only has Fission Product members. 
        """
        pymat = Material()
        pymat.mat_pointer[0] = self.mat_pointer.sub_fp(std.string(name))
        return pymat
        

    #
    # Operator Overloads
    #

    # Addition

    def __add_float__(Material x, double y):
        pymat = Material()
        pymat.mat_pointer[0] = x.mat_pointer[0] + y
        return pymat
        

    def __add_mass_stream__(Material x, Material y):
        pymat = Material()
        pymat.mat_pointer[0] = x.mat_pointer[0] + y.mat_pointer[0]
        return pymat


    def __add__(x, y): 
        if isinstance(x, Material) and isinstance(y, Material):
            return x.__add_mass_stream__(y)
        elif isinstance(y, float):
            return x.__add_float__(y)
        elif isinstance(x, float):
            return y.__add_float__(x)
        elif isinstance(y, int):
            return x.__add_float__(float(y))
        elif isinstance(x, int):
            return y.__add_float__(float(x))
        else:
            return NotImplemented


    # Multiplication

    def __mul_float__(Material x, double y):
        pymat = Material()
        pymat.mat_pointer[0] = x.mat_pointer[0] * y
        return pymat


    def __mul__(x, y):
        if isinstance(y, float):
            return x.__mul_float__(y)
        elif isinstance(x, float):
            return y.__mul_float__(x)
        elif isinstance(y, int):
            return x.__mul_float__(float(y))
        elif isinstance(x, int):
            return y.__mul_float__(float(x))
        else:
            return NotImplemented


    # Division

    def __div_float__(Material self, double y):
        pymat = Material()
        pymat.mat_pointer[0] = self.mat_pointer[0] / y
        return pymat


    def __div__(Material self, y):
        if isinstance(y, float):
            return self.__div_float__(y)
        elif isinstance(y, int):
            return self.__div_float__(float(y))
        else:
            return NotImplemented


    def __rdiv__(Material self, y):
        return self.__div__(y)

    
    def __truediv__(Material self, y):
        return self.__div__(y)




###########################
### Material Converters ###
###########################

# <string, Material *>

cdef cpp_map[std.string, matp] dict_to_map_str_matp(dict pydict):
    cdef Material pymat 
    cdef cpp_material.Material * cpp_matp
    cdef cpp_map[std.string, matp] cppmap = cpp_map[std.string, matp]()

    for key, value in pydict.items():
        pymat = value
        cpp_matp = pymat.mat_pointer
        cppmap[std.string(key)] = cpp_matp

    return cppmap


cdef dict map_to_dict_str_matp(cpp_map[std.string, matp] cppmap):
    pydict = {}
    cdef Material pymat 
    cdef cpp_map[std.string, matp].iterator mapiter = cppmap.begin()

    while mapiter != cppmap.end():
        pymat = Material()
        pymat.mat_pointer[0] = deref(deref(mapiter).second)
        pydict[deref(mapiter).first.c_str()] = pymat
        inc(mapiter)

    return pydict

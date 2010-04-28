#    Copyright 2010 Christoffer Lervag

module DICOM

  # Class for handling information related to a Data Element.
  class DataElement

    # Include the Elements mixin module:
    include Elements

    # Initialize a DataElement instance. Takes a tag string, a value and a hash of options as parameters.
    #
    # === Parameters
    #
    # * <tt>tag</tt> -- A string which identifies the tag of  the Data Element.
    # * <tt>value</tt> -- A custom value to be encoded as the Data Element binary string, or in some cases, a pre-encoded binary string.
    # * <tt>options</tt> -- A hash of parameters.
    #
    # === Options
    #
    # * <tt>:bin</tt> -- String. If both value and binary string has already been decoded/encoded, the binary string can be supplied with this option to avoid it being processed again.
    # * <tt>:encoded</tt> -- Boolean. If the value parameter contains a pre-encoded binary, this boolean needs to be set. In this case the DataElement will not have a formatted value.
    # * <tt>:name</tt> - String. The name of the Data Element may be specified upon creation. If not, a query will be done against the library.
    # * <tt>:parent</tt> - Item or DObject instance which the newly created DataElement instance belongs to.
    # * <tt>:vr</tt> -- String. If a private Data Element is created with a custom value, this needs to be specified to enable the encoding of the value.
    def initialize(tag, value, options={})
      # Set instance variables:
      @tag = tag
      # Value may in some cases be the binary string:
      unless options[:encoded]
        @value = value
        @bin = options[:bin] || ""
      else
        @bin = value
      end
      # We may beed to retrieve name and vr from the library:
      if options[:name] and options[:vr]
        @name = options[:name]
        @vr = options[:vr]
      else
        name, vr = LIBRARY.get_name_vr(tag)
        @name = options[:name] || name
        @vr = options[:vr] || vr
      end
      # Let the binary decide the length:
      @length = @bin.length
      # Manage the parent relation if specified:
      if options[:parent]
        @parent = options[:parent]
        @parent.add(self)
      end
      
    end

    # Returns false (a boolean used to check whether an element has children or not).
    def children?
      return false
    end

  end # of class
end # of module
#    Copyright 2009-2010 Christoffer Lervag

module DICOM

  # This class contains code for handling the client side of DICOM TCP/IP network communication.
  #
  #--
  # FIXME: The code which waits for incoming network packets seems to be very CPU intensive. Perhaps there is a more elegant way to wait for incoming messages?
  #
  class DClient

    # The name of this client (application entity).
    attr_accessor :ae
    # The name of the server (application entity).
    attr_accessor :host_ae
    # The IP adress of the server.
    attr_accessor :host_ip
    # The maximum allowed size of network packages (in bytes). 
    attr_accessor :max_package_size
    # The network port to be used.
    attr_accessor :port
    # The maximum period the client will wait on an answer from a server before aborting the communication.
    attr_accessor :timeout
    # A boolean which defines if notices/warnings/errors will be printed to the screen (true) or not (false).
    attr_accessor :verbose
    # An array, where each index contains a hash with the data elements received in a command response (with tags as keys).
    attr_reader :command_results
    # An array, where each index contains a hash with the data elements received in a data response (with tags as keys).
    attr_reader :data_results
    # An array containing any error messages recorded.
    attr_reader :errors
    # An array containing any status messages recorded.
    attr_reader :notices

    # Creates a DClient instance.
    #
    # === Parameters
    #
    # * <tt>host_ip</tt> -- String. The IP adress of the server which you are going to communicate with.
    # * <tt>port</tt> -- Fixnum. The network port to be used.
    # * <tt>options</tt> -- A hash of parameters.
    #
    # === Options
    #
    # * <tt>:ae</tt> -- String. The name of this client (application entity).
    # * <tt>:host_ae</tt> -- String. The name of the server (application entity).
    # * <tt>:max_package_size</tt> -- Fixnum. The maximum allowed size of network packages (in bytes). 
    # * <tt>:timeout</tt> -- Fixnum. The maximum period the server will wait on an answer from a client before aborting the communication.
    # * <tt>:verbose</tt> -- Boolean. If set to false, the DObject instance will run silently and not output warnings and error messages to the screen. Defaults to true.
    #
    # === Examples
    #
    #   # Create a client instance using default settings:
    #   node = DICOM::DClient.new("10.1.25.200", 104)
    #
    def initialize(host_ip, port, options={})
      require 'socket'
      # Required parameters:
      @host_ip = host_ip
      @port = port
      # Optional parameters (and default values):
      @ae =  options[:ae]  || "RUBY_DICOM"
      @host_ae =  options[:host_ae]  || "DEFAULT"
      @max_package_size = options[:max_package_size] || 32768 # 16384
      @timeout = options[:timeout] || 10 # seconds
      @min_length = 12 # minimum number of bytes to expect in an incoming transmission
      @verbose = options[:verbose]
      @verbose = true if @verbose == nil # Default verbosity is 'on'.
      # Other instance variables:
      @errors = Array.new # errors and warnings are put in this array
      @notices = Array.new # information on successful transmissions are put in this array
      # Variables used for monitoring state of transmission:
      @association = nil # DICOM Association status
      @request_approved = nil # Status of our DICOM request
      @release = nil # Status of received, valid release response
      # Results from a query:
      @command_results = Array.new
      @data_results = Array.new
      # Set default values like transfer syntax, user information, endianness:
      set_default_values
      set_user_information_array
      # Initialize the network package handler:
      @link = Link.new(:ae => @ae, :host_ae => @host_ae, :max_package_size => @max_package_size, :timeout => @timeout)
    end

    # Tests the connection to the server by performing a C-ECHO.
    #
    def echo
      success = false
      # Verification SOP Class:
      @abstract_syntaxes = [VERIFICATION_SOP]
      perform_echo
    end

    # Queries a service class provider for images that match the specified criteria.
    #
    # === Parameters
    #
    # * <tt>options</tt> -- A hash of parameters.
    #
    # === Options
    #
    # * <tt>"0008,0018"</tt> --  SOP Instance UID
    # * <tt>"0008,0052"</tt> -- Query/Retrieve Level
    # * <tt>"0020,000D"</tt> -- Study Instance UID
    # * <tt>"0020,000E"</tt> -- Series Instance UID
    # * <tt>"0020,0013"</tt> -- Instance Number
    #
    # === Examples
    #
    #   node.find_images("0020,000D" => "1.2.840.1145.342", "0020,000E" => "1.3.6.1.4.1.2452.6.687844")
    #
    def find_images(options={})
      # Study Root Query/Retrieve Information Model - FIND:
      @abstract_syntaxes = ["1.2.840.10008.5.1.4.1.2.2.1"]
      # Prepare data elements for this operation:
      set_data_fragment_find_images
      set_data_options(options)
      perform_find
      return @data_results
    end

    # Queries a service class provider for patients that match the specified criteria.
    #
    # === Parameters
    #
    # * <tt>options</tt> -- A hash of parameters.
    #
    # === Options
    #
    # * <tt>"0008,0052"</tt> -- Query/Retrieve Level
    # * <tt>"0010,0010"</tt> -- Patient's Name
    # * <tt>"0010,0020"</tt> -- Patient ID
    # * <tt>"0010,0030"</tt> -- Patient's Birth Date
    # * <tt>"0010,0040"</tt> -- Patient's Sex
    #
    # === Examples
    #
    #   node.find_patients("0010,0010" => "James*")
    #
    def find_patients(options={})
      # Patient Root Query/Retrieve Information Model - FIND:
      @abstract_syntaxes = ["1.2.840.10008.5.1.4.1.2.1.1"]
      # Prepare data elements for this operation:
      set_data_fragment_find_patients
      set_data_options(options)
      perform_find
      return @data_results
    end

    # Queries a service class provider for series that match the specified criteria.
    #
    # === Parameters
    #
    # * <tt>options</tt> -- A hash of parameters.
    #
    # === Options
    #
    # * <tt>"0008,0052"</tt> -- Query/Retrieve Level
    # * <tt>"0008,0060"</tt> -- Modality
    # * <tt>"0008,103E"</tt> -- Series Description
    # * <tt>"0020,000D"</tt> -- Study Instance UID
    # * <tt>"0020,000E"</tt> -- Series Instance UID
    # * <tt>"0020,0011"</tt> -- Series Number
    #
    # === Examples
    #
    #   node.find_series("0020,000D" => "1.2.840.1145.342")
    #
    def find_series(options={})
      # Study Root Query/Retrieve Information Model - FIND:
      @abstract_syntaxes = ["1.2.840.10008.5.1.4.1.2.2.1"]
      # Prepare data elements for this operation:
      set_data_fragment_find_series
      set_data_options(options)
      perform_find
      return @data_results
    end

    # Queries a service class provider for studies that match the specified criteria.
    #
    # === Parameters
    #
    # * <tt>options</tt> -- A hash of parameters.
    #
    # === Options
    #
    # * <tt>"0008,0020"</tt> -- Study Date
    # * <tt>"0008,0030"</tt> -- Study Time
    # * <tt>"0008,0050"</tt> -- Accession Number
    # * <tt>"0008,0052"</tt> -- Query/Retrieve Level
    # * <tt>"0008,0090"</tt> -- Referring Physician's Name
    # * <tt>"0008,1030"</tt> -- Study Description
    # * <tt>"0008,1060"</tt> -- Name of Physician(s) Reading Study
    # * <tt>"0010,0010"</tt> -- Patient's Name
    # * <tt>"0010,0020"</tt> -- Patient ID
    # * <tt>"0010,0030"</tt> -- Patient's Birth Date
    # * <tt>"0010,0040"</tt> -- Patient's Sex
    # * <tt>"0020,000D"</tt> -- Study Instance UID
    # * <tt>"0020,0010"</tt> -- Study ID
    #
    # === Examples
    #
    #   node.find_studies("0008,0020" => "20090604-", "0010,000D" => "123456789")
    #
    def find_studies(options={})
      # Study Root Query/Retrieve Information Model - FIND:
      @abstract_syntaxes = ["1.2.840.10008.5.1.4.1.2.2.1"]
      # Prepare data elements for this operation:
      set_data_fragment_find_studies
      set_data_options(options)
      perform_find
      return @data_results
    end

    # Retrieves a DICOM file from a service class provider (SCP/PACS).
    #
    # === Restrictions
    #
    # * This method has never actually been tested, and as such, it is probably not working! Feedback is welcome.
    #
    # === Parameters
    #
    # * <tt>path</tt> -- The path where incoming files will be saved.
    # * <tt>options</tt> -- A hash of parameters.
    #
    # === Options
    #
    # * <tt>"0008,0018"</tt> -- SOP Instance UID
    # * <tt>"0008,0052"</tt> -- Query/Retrieve Level
    # * <tt>"0020,000D"</tt> -- Study Instance UID
    # * <tt>"0020,000E"</tt> -- Series Instance UID
    # === Examples
    #
    #   node.get_image("c:/dicom/", "0008,0018" => sop_uid, "0020,000D" => study_uid, "0020,000E" => series_uid)
    #
    def get_image(path, options={})
      # Study Root Query/Retrieve Information Model - GET:
      @abstract_syntaxes = ["1.2.840.10008.5.1.4.1.2.2.3"]
      # Transfer the current options to the data_elements hash:
      set_command_fragment_get
      # Prepare data elements for this operation:
      set_data_fragment_get_image
      set_data_options(options)
      perform_get(path)
    end

    # Moves a single image to a DICOM server.
    #
    # === Notes
    #
    # * This DICOM node must be a third party (not yourself).
    #
    # === Parameters
    #
    # * <tt>destination</tt> -- String. The name (AE title) of the DICOM server which will receive the file.
    # * <tt>options</tt> -- A hash of parameters.
    #
    # === Options
    #
    # * <tt>"0008,0018"</tt> -- SOP Instance UID
    # * <tt>"0008,0052"</tt> -- Query/Retrieve Level
    # * <tt>"0020,000D"</tt> -- Study Instance UID
    # * <tt>"0020,000E"</tt> -- Series Instance UID
    #
    # === Examples
    #
    #   node.move_image("SOME_SERVER", "0008,0018" => sop_uid, "0020,000D" => study_uid, "0020,000E" => series_uid)
    #
    def move_image(destination, options={})
      # Study Root Query/Retrieve Information Model - MOVE:
      @abstract_syntaxes = ["1.2.840.10008.5.1.4.1.2.2.2"]
      # Transfer the current options to the data_elements hash:
      set_command_fragment_move(destination)
      # Prepare data elements for this operation:
      set_data_fragment_move_image
      set_data_options(options)
      perform_move
    end

    # Move an entire study to a DICOM server.
    #
    # === Notes
    #
    # * This DICOM node must be a third party (not yourself).
    #
    # === Parameters
    #
    # * <tt>destination</tt> -- String. The name (AE title) of the DICOM server which will receive the files.
    # * <tt>options</tt> -- A hash of parameters.
    #
    # === Options
    #
    # * <tt>"0008,0052"</tt> -- Query/Retrieve Level
    # * <tt>"0010,0020"</tt> -- Patient ID
    # * <tt>"0020,000D"</tt> -- Study Instance UID
    #
    # === Examples
    #
    #   node.move_study("SOME_SERVER", "0010,0020" => pat_id, "0020,000D" => study_uid)
    #
    def move_study(destination, options={})
      # Study Root Query/Retrieve Information Model - MOVE:
      @abstract_syntaxes = ["1.2.840.10008.5.1.4.1.2.2.2"]
      # Transfer the current options to the data_elements hash:
      set_command_fragment_move(destination)
      # Prepare data elements for this operation:
      set_data_fragment_move_study
      set_data_options(options)
      perform_move
    end

    # Sends one or more DICOM files to a service class provider (SCP/PACS).
    #
    # === Parameters
    #
    # * <tt>files</tt> -- A single file path or an array of paths, or a DObject or an array of DObject instances.
    #
    # === Examples
    #
    #   node.send("my_file.dcm")
    #
    def send(files)
      # Prepare the DICOM object(s):
      objects, @abstract_syntaxes, success, message = load_files(files)
      if success
        # Open a DICOM link:
        establish_association
        if @association
          if @request_approved
            # Continue with our c-store operation, since our request was accepted.
            # Handle the transmission:
            perform_send(objects)
          end
        end
        # Close the DICOM link:
        establish_release
      else
        # Failed when loading the specified parameter as DICOM file(s). Will not transmit.
        add_error(message)
      end
    end

    # Tests the connection to the server in a very simple way  by negotiating an association and then releasing it.
    #
    def test
      add_notice("TESTING CONNECTION...")
      success = false
      # Verification SOP Class:
      @abstract_syntaxes = [VERIFICATION_SOP]
      # Open a DICOM link:
      establish_association
      if @association
        if @request_approved
          success = true
        end
        # Close the DICOM link:
        establish_release
      end
      if success
        add_notice("TEST SUCCSESFUL!")
      else
        add_error("TEST FAILED!")
      end
      return success
    end


    # Following methods are private:
    private


    # Adds a warning or error message to the instance array holding messages,
    # and prints the information to the screen if verbose is set.
    #
    # === Parameters
    #
    # * <tt>error</tt> -- A single error message or an array of error messages.
    #
    def add_error(error)
      puts error if @verbose
      @errors << error
    end

    # Adds a notice (information regarding progress or successful communications) to the instance array,
    # and prints the information to the screen if verbose is set.
    #
    # === Parameters
    #
    # * <tt>notice</tt> -- A single status message or an array of status messages.
    #
    def add_notice(notice)
      puts notice if @verbose
      @notices << notice
    end

    # Opens a TCP session with the server, and handles the association request as well as the response.
    #
    def establish_association
      # Reset some variables:
      @association = false
      @request_approved = false
      # Initiate the association:
      @link.build_association_request(@application_context_uid, @abstract_syntaxes, @transfer_syntax, @user_information)
      @link.start_session(@host_ip, @port)
      @link.transmit
      info = @link.receive_multiple_transmissions.first
      # Interpret the results:
      if info[:valid]
        if info[:pdu] == PDU_ASSOCIATION_ACCEPT
          # Values of importance are extracted and put into instance variables:
          @association = true
          @max_pdu_length = info[:max_pdu_length]
          add_notice("Association successfully negotiated with host #{@host_ae} (#{@host_ip}).")
          # Check if all our presentation contexts was accepted by the host:
          process_presentation_context_response(info[:pc])
        else
          add_error("Association was denied from host #{@host_ae} (#{@host_ip})!")
        end
      end
    end

    # Handles the release request along with the response, as well as closing the TCP connection.
    #
    def establish_release
      @release = false
      if @abort
        @link.stop_session
        add_notice("Association has been closed. (#{@host_ae}, #{@host_ip})")
      else
        unless @link.session.closed?
          @link.build_release_request
          @link.transmit
          info = @link.receive_single_transmission.first
          @link.stop_session
          if info[:pdu] == PDU_RELEASE_RESPONSE
            add_notice("Association released properly from host #{@host_ae}.")
          else
            add_error("Association released from host #{@host_ae}, but a release response was not registered.")
          end
        else
          add_error("Connection was closed by the host (for some unknown reason) before the association could be released properly.")
        end
      end
      @abort = false
    end

    # Loads one or more DICOM files.
    # Returns an array of DObject instances, an array of unique abstract syntaxes found among the files, a status boolean and a message string.
    #
    # === Parameters
    #
    # * <tt>files</tt> -- A single file path or an array of paths, or a DObject or an array of DObject instances.
    #
    def load_files(files)
      status = true
      message = ""
      objects = Array.new
      abstracts = Array.new
      files = [files] unless files.is_a?(Array)
      files.each do |file|
        if file.is_a?(String)
          obj = DObject.new(file, :verbose => false)
          if obj.read_success
            # Load the DICOM object and its abstract syntax:
            objects << obj
            abstracts << obj.value("0008,0016")
          else
            status = false
            message = "Failed to successfully parse a DObject for the following string: #{file}"
          end
        elsif file.is_a?(DObject)
          # Load the DICOM object and its abstract syntax:
          objects << obj
          abstracts << obj.value("0008,0016")
        else
          status = false
          message = "Array contains invalid object #{file}."
        end
      end
      return objects, abstracts.uniq, status, message
    end

    # Handles the communication involved in a DICOM C-ECHO.
    # Build the necessary strings and send the command and data element that makes up the echo request.
    # Listens for and interpretes the incoming echo response.
    #
    def perform_echo
      # Open a DICOM link:
      establish_association
      if @association
        if @request_approved
          # Continue with our echo, since the request was accepted.
          # Set the query command elements array:
          set_command_fragment_echo
          presentation_context_id = @approved_syntaxes.to_a.first[1][0] # ID of first (and only) syntax in this Hash.
          @link.build_command_fragment(PDU_DATA, presentation_context_id, COMMAND_LAST_FRAGMENT, @command_elements)
          @link.transmit
          # Listen for incoming responses and interpret them individually, until we have received the last command fragment.
          segments = @link.receive_multiple_transmissions
          process_returned_data(segments)
          # Print stuff to screen?
        end
        # Close the DICOM link:
        establish_release
      end
    end

    # Handles the communication involved in a DICOM query (C-FIND).
    # Build the necessary strings and send the command and data element that makes up the query.
    # Listens for and interpretes the incoming query responses.
    #
    def perform_find
      # Open a DICOM link:
      establish_association
      if @association
        if @request_approved
          # Continue with our query, since the request was accepted.
          # Set the query command elements array:
          set_command_fragment_find
          presentation_context_id = @approved_syntaxes.to_a.first[1][0] # ID of first (and only) syntax in this Hash.
          @link.build_command_fragment(PDU_DATA, presentation_context_id, COMMAND_LAST_FRAGMENT, @command_elements)
          @link.transmit
          @link.build_data_fragment(@data_elements, presentation_context_id)
          @link.transmit
          # A query response will typically be sent in multiple, separate packets.
          # Listen for incoming responses and interpret them individually, until we have received the last command fragment.
          segments = @link.receive_multiple_transmissions
          process_returned_data(segments)
        end
        # Close the DICOM link:
        establish_release
      end
    end

    # Handles the communication involved in a DICOM C-GET.
    # Builds and sends command & data fragment, then receives the incoming file data.
    #
    #--
    # FIXME: This method has never actually been tested, since it is difficult to find a host that accepts a c-get-rq.
    #
    def perform_get(path)
      # Open a DICOM link:
      establish_association
      if @association
        if @request_approved
          # Continue with our operation, since the request was accepted.
          presentation_context_id = @approved_syntaxes.to_a.first[1][0] # ID of first (and only) syntax in this Hash.
          @link.build_command_fragment(PDU_DATA, presentation_context_id, COMMAND_LAST_FRAGMENT, @command_elements)
          @link.transmit
          @link.build_data_fragment(@data_elements, presentation_context_id)
          @link.transmit
          # Listen for incoming file data:
          success = @link.handle_incoming_data(path)
          if success
            # Send confirmation response:
            @link.handle_response
          end
        end
        # Close the DICOM link:
        establish_release
      end
    end

    # Handles the communication involved in DICOM C-MOVE.
    # Build the necessary strings and sends the command element that makes up the move request.
    # Listens for and interpretes the incoming move response.
    #
    def perform_move
      # Open a DICOM link:
      establish_association
      if @association
        if @request_approved
          # Continue with our operation, since the request was accepted.
          presentation_context_id = @approved_syntaxes.to_a.first[1][0] # ID of first (and only) syntax in this Hash.
          @link.build_command_fragment(PDU_DATA, presentation_context_id, COMMAND_LAST_FRAGMENT, @command_elements)
          @link.transmit
          @link.build_data_fragment(@data_elements, presentation_context_id)
          @link.transmit
          # Receive confirmation response:
          segments = @link.receive_single_transmission
          process_returned_data(segments)
        end
        # Close the DICOM link:
        establish_release
      end
    end

    # Handles the communication involved in DICOM C-STORE.
    # For each file, builds and sends command fragment, then builds and sends the data fragments that
    # conveys the information from the selected DICOM file.
    #
    def perform_send(objects)
      objects.each_with_index do |obj, index|
        # Gather necessary information from the object (SOP Class & Instance UID):
        modality = obj.value("0008,0016")
        instance = obj.value("0008,0018")
        if modality and instance
          # Only send the image if its modality has been accepted by the receiver:
          if @approved_syntaxes[modality]
            # Set the command array to be used:
            message_id = index + 1
            set_command_fragment_store(modality, instance, message_id)
            # Find context id and transfer syntax:
            presentation_context_id = @approved_syntaxes[modality][0]
            selected_transfer_syntax = @approved_syntaxes[modality][1]
            # Encode our DICOM object to a binary string which is split up in pieces, sufficiently small to fit within the specified maximum pdu length:
            # Set the transfer syntax of the DICOM object equal to the one accepted by the SCP:
            obj.transfer_syntax = selected_transfer_syntax
            max_header_length = 14
            data_packages = obj.encode_segments(@max_pdu_length - max_header_length)
            @link.build_command_fragment(PDU_DATA, presentation_context_id, COMMAND_LAST_FRAGMENT, @command_elements)
            @link.transmit
            # Transmit all but the last data strings:
            last_data_package = data_packages.pop
            data_packages.each do |data_package|
              @link.build_storage_fragment(PDU_DATA, presentation_context_id, DATA_MORE_FRAGMENTS, data_package)
              @link.transmit
            end
            # Transmit the last data string:
            @link.build_storage_fragment(PDU_DATA, presentation_context_id, DATA_LAST_FRAGMENT, last_data_package)
            @link.transmit
            # Receive confirmation response:
            segments = @link.receive_single_transmission
            process_returned_data(segments)
          end
        else
          add_error("Error: Unable to extract SOP Class UID and/or SOP Instance UID for this DICOM object. File will not be sent to its destination.")
        end
      end
    end

    # Processes the presentation contexts that are received in the association response
    # to extract the transfer syntaxes which have been accepted for the various abstract syntaxes.
    #
    # === Parameters
    #
    # * <tt>presentation_contexts</tt> -- An array where each index contains a presentation context hash.
    #
    def process_presentation_context_response(presentation_contexts)
      # Storing approved syntaxes in an Hash with the syntax as key and the value being an array with presentation context ID and the transfer syntax chosen by the SCP.
      @approved_syntaxes = Hash.new
      rejected = Hash.new
      # Reset the presentation context instance variable:
      @link.presentation_contexts = Hash.new
      presentation_contexts.each do |pc|
        # Determine what abstract syntax this particular presentation context's id corresponds to:
        id = pc[:presentation_context_id]
        raise "Error! Even presentation context ID received in the association response. This is not allowed according to the DICOM standard!" if id[0] == 0 # If even number.
        index = (id-1)/2
        abstract_syntax = @abstract_syntaxes[index]
        if pc[:result] == 0
          @approved_syntaxes[abstract_syntax] = [id, pc[:transfer_syntax]]
          @link.presentation_contexts[id] = pc[:transfer_syntax]
        else
          rejected[abstract_syntax] = [id, pc[:transfer_syntax]]
        end
      end
      if rejected.length == 0
        @request_approved = true
        if @approved_syntaxes.length == 1
          add_notice("The presentation context was accepted by host #{@host_ae}.")
        else
          add_notice("All #{@approved_syntaxes.length} presentation contexts were accepted by host #{@host_ae} (#{@host_ip}).")
        end
      else
        @request_approved = false
        add_error("One or more of your presentation contexts were denied by host #{@host_ae}!")
        @approved_syntaxes.each_key {|a| add_error("APPROVED: #{LIBRARY.get_syntax_description(a)}")}
        rejected.each_key {|r| add_error("REJECTED: #{LIBRARY.get_syntax_description(r)}")}
      end
    end

    # Processes the array of information hashes that was returned from the interaction with the SCP
    # and transfers it to the instance variables where command and data results are stored.
    #
    def process_returned_data(segments)
      # Reset command results arrays:
      @command_results = Array.new
      @data_results = Array.new
      # Try to extract data:
      segments.each do |info|
        if info[:valid]
          # Determine if it is command or data:
          if info[:presentation_context_flag] == COMMAND_LAST_FRAGMENT
            @command_results << info[:results]
          elsif info[:presentation_context_flag] == DATA_LAST_FRAGMENT
            @data_results << info[:results]
          end
        end
      end
    end

    # Sets the command elements used in a C-ECHO-RQ.
    #
    def set_command_fragment_echo
      @command_elements = [
        ["0000,0002", "UI", @abstract_syntaxes.first], # Affected SOP Class UID
        ["0000,0100", "US", C_ECHO_RQ],
        ["0000,0110", "US", DEFAULT_MESSAGE_ID],
        ["0000,0800", "US", NO_DATA_SET_PRESENT]
      ]
    end

    # Sets the command elements used in a C-FIND-RQ.
    #
    # === Notes
    #
    # * This setup is used for all types of queries.
    #
    def set_command_fragment_find
      @command_elements = [
        ["0000,0002", "UI", @abstract_syntaxes.first], # Affected SOP Class UID
        ["0000,0100", "US", C_FIND_RQ],
        ["0000,0110", "US", DEFAULT_MESSAGE_ID],
        ["0000,0700", "US", 0], # Priority: 0: medium
        ["0000,0800", "US", DATA_SET_PRESENT]
      ]
    end

    # Sets the command elements used in a C-GET-RQ.
    #
    def set_command_fragment_get
      @command_elements = [
        ["0000,0002", "UI", @abstract_syntaxes.first], # Affected SOP Class UID
        ["0000,0100", "US", C_GET_RQ],
        ["0000,0600", "AE", @ae], # Destination is ourselves
        ["0000,0700", "US", 0], # Priority: 0: medium
        ["0000,0800", "US", DATA_SET_PRESENT]
      ]
    end

    # Sets the command elements used in a C-MOVE-RQ.
    #
    def set_command_fragment_move(destination)
      @command_elements = [
        ["0000,0002", "UI", @abstract_syntaxes.first], # Affected SOP Class UID
        ["0000,0100", "US", C_MOVE_RQ],
        ["0000,0110", "US", DEFAULT_MESSAGE_ID],
        ["0000,0600", "AE", destination],
        ["0000,0700", "US", 0], # Priority: 0: medium
        ["0000,0800", "US", DATA_SET_PRESENT]
      ]
    end

    # Sets the command elements used in a C-STORE-RQ.
    #
    def set_command_fragment_store(modality, instance, message_id)
      @command_elements = [
        ["0000,0002", "UI", modality], # Affected SOP Class UID
        ["0000,0100", "US", C_STORE_RQ],
        ["0000,0110", "US", message_id],
        ["0000,0700", "US", 0], # Priority: 0: medium
        ["0000,0800", "US", DATA_SET_PRESENT],
        ["0000,1000", "UI", instance] # Affected SOP Instance UID
      ]
    end

    # Sets the data elements used in a query for the images of a particular series.
    #
    def set_data_fragment_find_images
      @data_elements = [
        ["0008,0018", ""], # SOP Instance UID
        ["0008,0052", "IMAGE"], # Query/Retrieve Level:  "IMAGE"
        ["0020,000D", ""], # Study Instance UID
        ["0020,000E", ""], # Series Instance UID
        ["0020,0013", ""] # Instance Number
      ]
    end

    # Sets the data elements used in a query for patients.
    #
    def set_data_fragment_find_patients
      @data_elements = [
        ["0008,0052", "PATIENT"], # Query/Retrieve Level:  "PATIENT"
        ["0010,0010", ""], # Patient's Name
        ["0010,0020", ""], # Patient ID
        ["0010,0030", ""], # Patient's Birth Date
        ["0010,0040", ""] # Patient's Sex
      ]
    end

    # Sets the data elements used in a query for the series of a particular study.
    #
    def set_data_fragment_find_series
      @data_elements = [
        ["0008,0052", "SERIES"], # Query/Retrieve Level: "SERIES"
        ["0008,0060", ""], # Modality
        ["0008,103E", ""], # Series Description
        ["0020,000D", ""], # Study Instance UID
        ["0020,000E", ""], # Series Instance UID
        ["0020,0011", ""] # Series Number
      ]
    end

    # Sets the data elements used in a query for studies.
    #
    def set_data_fragment_find_studies
      @data_elements = [
        ["0008,0020", ""], # Study Date
        ["0008,0030", ""], # Study Time
        ["0008,0050", ""], # Accession Number
        ["0008,0052", "STUDY"], # Query/Retrieve Level:  "STUDY"
        ["0008,0090", ""], # Referring Physician's Name
        ["0008,1030", ""], # Study Description
        ["0008,1060", ""], # Name of Physician(s) Reading Study
        ["0010,0010", ""], # Patient's Name
        ["0010,0020", ""], # Patient ID
        ["0010,0030", ""], # Patient's Birth Date
        ["0010,0040", ""], # Patient's Sex
        ["0020,000D", ""], # Study Instance UID
        ["0020,0010", ""] # Study ID
      ]
    end

    # Sets the data elements used for an image C-GET-RQ.
    #
    def set_data_fragment_get_image
      @data_elements = [
        ["0008,0018", ""], # SOP Instance UID
        ["0008,0052", "IMAGE"], # Query/Retrieve Level:  "IMAGE"
        ["0020,000D", ""], # Study Instance UID
        ["0020,000E", ""] # Series Instance UID
      ]
    end

    # Sets the data elements used for an image C-MOVE-RQ.
    #
    def set_data_fragment_move_image
      @data_elements = [
        ["0008,0018", ""], # SOP Instance UID
        ["0008,0052", "IMAGE"], # Query/Retrieve Level:  "IMAGE"
        ["0020,000D", ""], # Study Instance UID
        ["0020,000E", ""] # Series Instance UID
      ]
    end

    # Sets the data elements used in a study C-MOVE-RQ.
    #
    def set_data_fragment_move_study
      @data_elements = [
        ["0008,0052", "STUDY"], # Query/Retrieve Level:  "STUDY"
        ["0010,0020", ""], # Patient ID
        ["0020,000D", ""] # Study Instance UID
      ]
    end

    # Transfers the user query options to the @data_elements instance array.
    #
    # === Restrictions
    #
    # * Only tag & value pairs for tags which are predefined for the specific query type will be stored!
    #
    def set_data_options(options)
      options.each_pair do |key, value|
        tags = @data_elements.transpose[0]
        i = tags.index(key)
        if i
          @data_elements[i][1] = value
        end
      end
    end

    # Sets the default values for proposed transfer syntaxes.
    #
    def set_default_values
      # DICOM Application Context Name (unknown if this will vary or is always the same):
      @application_context_uid = APPLICATION_CONTEXT
      # Transfer syntax string array (preferred syntax appearing first):
      @transfer_syntax = [IMPLICIT_LITTLE_ENDIAN, EXPLICIT_LITTLE_ENDIAN, EXPLICIT_BIG_ENDIAN]
    end

    # Sets the @user_information instance array.
    #
    # === Notes
    #
    # Each user information item is a three element array consisting of: item type code, VR & value.
    #
    def set_user_information_array
      @user_information = [
        [ITEM_MAX_LENGTH, "UL", @max_package_size],
        [ITEM_IMPLEMENTATION_UID, "STR", UID],
        [ITEM_IMPLEMENTATION_VERSION, "STR", NAME]
      ]
    end

  end
end
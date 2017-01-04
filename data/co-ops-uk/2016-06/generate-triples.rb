# This script is usually called from the Makefile - look there for usage examples.
#
# Note on testing this script:
#   Recall that output is written to a directory (option --output-dir)
#   Note also that you can generate data from just the first few lines of the CSV files (option --max-csv-rows)
#   Before making changes, run the script (usually via `make generate-data`).
#   Save the output dir:
#     $ mv generated-data generated-data.old
#   Now change and re-run the script, and compare the differences:
#     $ diff -r -I  'nodeID' generated-data.old/ generated-data/
#   Note that nodeID will always be changing, as it is generated by the RDF lib.

require 'pp'
require 'optparse'
require 'cgi'
require 'csv'
require 'json'
require 'linkeddata'
require 'rdf/vocab'
require 'rdf'
require 'net/http'
$lib_dir = "../../../lib/p6/"
require_relative $lib_dir + 'xml'
require_relative $lib_dir + 'html'
require_relative $lib_dir + 'file'
require_relative $lib_dir + 'rdfxml'
require_relative $lib_dir + 'turtle'
require_relative $lib_dir + 'progress-counter'
require_relative $lib_dir + 'rdf-cache'

# Command line option parser based on https://docs.ruby-lang.org/en/2.1.0/OptionParser.html
class OptParse
  #
  # Return a structure describing the options.
  #
  def self.parse(args)
    # The options specified on the command line will be collected in *options*.
    # We set default values here.
    options = OpenStruct.new
    options.orgs_csv = nil
    options.outlets_csv = nil
    options.output_dir = nil
    options.map_app_sparql = nil
    options.one_big_file_suffix = nil
    options.uri_base = nil
    options.essglobal_uri = nil
    options.doc_url_base = nil
    options.dataset = nil
    options.css_files = []
    options.max_csv_rows = nil
    options.check_websites = false
    options.allow_blank_nodes = true

    opt_parser = OptionParser.new do |opts|
      opts.banner = "Usage: example.rb [options]"

      opts.separator ""
      opts.separator "Specific options:"

      # Mandatory argument.
      opts.on("--organizations-csv FILENAME",
              "Co-ops UK CSV file containing data on organizations") do |filename|
        options.orgs_csv = filename
      end

      # Mandatory argument.
      opts.on("--outlets-csv FILENAME",
              "Co-ops UK CSV file containing data on outlets") do |filename|
        options.outlets_csv = filename
      end

      # Mandatory argument.
      opts.on("--output-dir DIRECTORYNAME",
              "Name of directory for generated output") do |filename|
        options.output_dir = filename
      end

      # Mandatory argument.
      opts.on("--map-app-sparql FILENAME",
              "Name of file for generated SPARQL query for tha map-app") do |filename|
        options.map_app_sparql = filename
      end

      # Mandatory argument.
      opts.on("--one-big-file-suffix SUFFIX",
              "Name of file suffix for the one big file of RDF, generated for easy loading into OntoWiki") do |suffix|
        options.one_big_file_suffix = suffix
      end

      # Mandatory argument.
      opts.on("--uri-base URI",
	      "Base for URI of generated resources.",
	      "    e.g. http://data.solidarityeconomics.org/experimental") do |uri|
        options.uri_base = uri
      end
      
      # Mandatory argument.
      opts.on("--doc-url-base URI",
	      "Base for URI of where docs are stored. Typically, URIs based on uri-base will be 303 redirected to documents based on doc-url-base",
	      "    e.g. http://data.solidarityeconomics.org/doc/experimental") do |uri|
        options.doc_url_base = uri
      end

      # Mandatory argument.
      opts.on("--dataset NAME",
	      "Name of dataset - the next part of the path name after uri-base") do |filename|
        options.dataset = filename
      end

      # Mandatory argument.
      opts.on("--css-files x,y,z", Array,
	      "Name of a CSS files to be included") do |list|
        options.css_files = list
      end

      # Mandatory argument.
      opts.on("--essglobal-uri URI",
	      "Base URI for the essglobal vocabulary. e.g. http://purl.org/essglobal") do |uri|
        options.essglobal_uri = uri
      end

      opts.on("--max-csv-rows [ROWS]", Integer,
	      "Maximum number of rows of CSV to process from each input file, for testing") do |rows|
	options.max_csv_rows = rows
      end

      # Boolean switch.
      opts.on("--[no-]check-websites",
	      "Send HTTP reqiuest to all websites to check the return code (very time consuming)") do |v|
        options.check_websites = v
      end

      # Boolean switch.
      opts.on("--[no-]allow-blank-nodes",
	      "Allow blank nodes in the generated RDF. Without blank nodes, extra URIs have to be minted.") do |v|
        options.allow_blank_nodes = v
      end

      # Cast 'delay' argument to a Float.
      #opts.on("--delay N", Float, "Delay N seconds before executing") do |n|
        #options.delay = n
      #end

      # List of arguments.
      #opts.on("--list x,y,z", Array, "Example 'list' of arguments") do |list|
        #options.list = list
      #end

      # Optional argument with keyword completion.
      #opts.on("--type [TYPE]", [:text, :binary, :auto],
              #"Select transfer type (text, binary, auto)") do |t|
        #options.transfer_type = t
      #end

      # Boolean switch.
      opts.on("-v", "--[no-]verbose", "Run verbosely") do |v|
        options.verbose = v
      end

      opts.separator ""
      opts.separator "Common options:"

      # No argument, shows at tail.  This will print an options summary.
      # Try it and see!
      opts.on_tail("-h", "--help", "Show this message") do
        puts opts
        exit
      end

      # Another typical switch to print the version.
      #opts.on_tail("--version", "Show version") do
        #puts ::Version.join('.')
        #exit
      #end
    end

    opt_parser.parse!(args)
    options
  end  # parse()
end

# Parse command line options:
$options = OptParse.parse(ARGV)

$css_files_array = $options.css_files.map{|f| $options.dataset + "/" + f}
$essglobal = RDF::Vocabulary.new($options.essglobal_uri + "vocab/")
$essglobal_standard = RDF::Vocabulary.new($options.essglobal_uri + "standard/")
#$solecon = RDF::Vocabulary.new("http://solidarityeconomics.org/vocab#")
$ospostcode = RDF::Vocabulary.new("http://data.ordnancesurvey.co.uk/id/postcodeunit/")
$osspatialrelations = RDF::Vocabulary.new("http://data.ordnancesurvey.co.uk/ontology/spatialrelations/")
$prefixes = {
  vcard: RDF::Vocab::VCARD.to_uri.to_s,
  geo: RDF::Vocab::GEO.to_uri.to_s,
  essglobal: $essglobal.to_uri.to_s,
  #solecon: $solecon.to_uri.to_s,
  gr: RDF::Vocab::GR.to_uri.to_s,
  foaf: RDF::Vocab::FOAF.to_uri.to_s,
  ospostcode: $ospostcode.to_uri.to_s,
  osspatialrelations: $osspatialrelations.to_uri.to_s
}


def warning(msgs)
  msgs = msgs.kind_of?(Array) ? msgs : [msgs]
  $stderr.puts msgs.map{|m| "\nWARNING! #{m}"}.join 
end

# For testing the response HTTP code for a URL:
class UrlRes
  attr_reader :url, :http_code
  @@results = []
  def initialize(url)
    @url = url
    begin 
      u = URI.parse(url)
      req = Net::HTTP.new(u.host, u.port)
      res = req.request_head(u.path)
      @http_code = res.code || ""
    rescue
      @http_code = "Network error"
    end
    #puts "#{@http_code}: #{@url}"
    @@results << self
  end
  def self.all
    @@results
  end
end

class Collection < Array	# of Initiatives
  def make_graph
    graph = RDF::Graph.new
    each {|i|	# each initiative in the collection
      graph.insert([i.uri, RDF.type, Initiative.type_uri])
    }
    return graph
  end
  def html
    P6::Xml.xml(:html) {
      P6::Xml.xml(:head) {
	P6::Xml.xml(:title) { "Co-ops UK experimental dataset" } +
	$css_files_array.map {|f|
	  P6::Xml.xml(:link, rel: "stylesheet", type: "text/css", href: f)
	}.join
      } +
      P6::Xml.xml(:body) {
	P6::Xml.xml(:h1) { "Co-ops UK - experimental dataset" } +
	P6::Xml.xml(:p) { "The URI for this list is: " + P6::Html.link_to(uri.to_s) } +
	P6::Xml.xml(:p) { "See: " + P6::Html.link_to(Collection.about_uri.to_s, " about this dataset") + "." } +
	P6::Html.table(
	  headers: ["Co-op name", "URI" ],
	  rows: sort {|a, b| a.name <=> b.name}.map {|i| [i.name, P6::Html.link_to(i.uri.to_s)] }
	)
      }
    }
  end
  def about_html
    P6::Xml.xml(:html) {
      P6::Xml.xml(:head) {
	P6::Xml.xml(:title) { "Co-ops UK experimental dataset" } +
	$css_files_array.map {|f|
	  P6::Xml.xml(:link, rel: "stylesheet", type: "text/css", href: "../#{f}")
	}.join
      } +
      P6::Xml.xml(:body) {
	P6::Xml.xml(:h1) { "About this dataset"} +
	P6::Xml.xml(:p) { "Base URI: " + P6::Html.link_to(uri.to_s) } +
	P6::Xml.xml(:p) { 
	  "This is an experimental dataset, generated as part of the p6data project, which can be found " + 
	  P6::Html.link_to("https://github.com/p6data-coop", "on GitHub") +
	  ". Its experimental nature means that"
	} +
	P6::Xml.xml(:ul) {
	  P6::Xml.xml(:li) { "No test has been used to check if the items in this dataset are part of the solidarity economy." } +
	  P6::Xml.xml(:li) { "There's no guarantee that the URIs will be persistent. In fact it is most unlikely that they will be so." } +
	  P6::Xml.xml(:li) { "The triples included in the linked data have been chosen for the purpose of testing." } +
	  P6::Xml.xml(:li) { "Date is not included for co-ops in Northern Ireland, because the Ordnance Survey linked data for postcodes does not cover Northern Ireland." }
	}
      }
    }
  end
  def self.about_basename
    "#{basename}/about"
  end
  # for forming the name of the one big file with all the data contained in it:
  def self.one_big_file_basename
    "#{basename}#{$options.one_big_file_suffix}"
  end
  def self.about_uri
    RDF::URI("#{$options.uri_base}#{about_basename}")
  end

  def self.basename
    # Unlike the bash command basename, this is the basename without the extension.
    # TODO - rename basename_without_ext ?
    $options.dataset
  end
  def to_hash
    # Create a hash that maps each id to an array of initiatives (an array, because of duplicate ids). 
    h = Hash.new { |h, k| h[k] = [] }
    each {|i| h[i.id] << i }
    h
  end
  def resolve_duplicates
    # Currently, this method does not resolve duplicates, but reports on them.
    # The HTML report produced by method duplicates_html may be a better choice than this.
    outlets_headers = ["CUK Organisation ID", "Registered Name", "Outlet Name", "Street", "City", "State/Province", "Postcode", "Description", "Phone", "Website"]
    h = to_hash
    dups = h.select {|k, v| v.count > 1}
    pp dups
    dups.each {|k, v| 
      common, different = outlets_headers.partition{|x|
	v.map { |i| i.csv_row[x] }.uniq.count == 1
      }
      puts common.map { |x| "#{x}: #{v[0].csv_row[x]}" }.join("; ")
      puts v.map { |i| "    #{different.map { |x| "#{x}: #{i.csv_row[x]}" }.join("; ")}\n"}.join

      if v.uniq.count == 1
	puts "Duplicate entries in source data:"
	pp v
      end
    }
  end
  def websites_html(prog_ctr)
    # Report on the Websites.
    css = <<'ENDCSS'
td {vertical-align: top; }
td.common { background-color: #BFB; }
td.different { background-color: #FBB; } 
table {
    border-collapse: collapse;
}

table, th, td {
    border: 1px solid black;
}
td.first {
    border-top: 5px solid black;
}
ENDCSS
    each {|i|
      prog_ctr.step
      UrlRes.new(i.homepage) if (i.homepage.length > 0)
    }
    P6::Xml.xml(:html) {
      P6::Xml.xml(:head) {
	P6::Xml.xml(:title) { "Websites" }  +
	P6::Xml.xml(:style) { css }
      } + "\n" +
      P6::Xml.xml(:body) {
	P6::Xml.xml(:h1) { "Websites included in the Co-ops UK open dataset of June 2016" } +
	P6::Xml.xml(:p) { ""
	} + "\n" +
	P6::Html.table(
	  headers: ["URL", "HTTP code"],
	  rows: UrlRes.all.sort { |a, b| a.http_code <=> b.http_code }.map { |r| [r.url, r.http_code] }
	)
      }
    }
  end
  def duplicates_html
    # Column headers from the Outlets CSV file:
    id_headers = ["CUK Organisation ID", "Postcode"]
    outlets_headers = ["Registered Name", "Outlet Name", "Street", "City", "State/Province", "Description", "Phone", "Website"]

    # hash ( id => Initiative ) of all Initiatives with duplicate ids:
    dups = to_hash.select {|k, v| v.count > 1}
    css = <<'ENDCSS'
td {vertical-align: top; }
td.common { background-color: #BFB; }
td.different { background-color: #FBB; } 
table {
    border-collapse: collapse;
}

table, th, td {
    border: 1px solid black;
}
td.first {
    border-top: 5px solid black;
}
ENDCSS
    P6::Xml.xml(:html) {
      P6::Xml.xml(:head) {
	P6::Xml.xml(:title) { "Duplicates" }  +
	P6::Xml.xml(:style) { css }
      } + "\n" +
      P6::Xml.xml(:body) {
	P6::Xml.xml(:h1) { "Outlets with the same CUK ID and Postcode" } +
	P6::Xml.xml(:p) {
	  "The table shows all outlets with the same CUK Organisation ID and Postcode.
	  The other cells are coloured green if all outlets with the same CUK ID and Postcode have the same value, 
	  and red if they are differnt values."
	} +
	P6::Xml.xml(:p) {
	  "Green cells in the Outlet Name column may mean that the are genuine duplicates, which need to be cleaned"
	} +
	P6::Xml.xml(:p) {
	  "Something else revealed by this (nothing to do with duplicate outlets) is that some rows of the CSV have the Description column missing, so that the phone number becomes the description. Search for Long Sutton Post Office, for example."
	} + "\n" +
	P6::Xml.xml(:table) {
	  # Header row:
	  P6::Xml.xml(:tr) {
	    id_headers.map {|h| P6::Xml.xml(:th) { h } }.join +
	    outlets_headers.map {|h| P6::Xml.xml(:th) { h } }.join
	  } +

	  # Body rows:
	  dups.map {|k, v|
	    #common, different = outlets_headers.partition{|x|
	      #v.map { |i| i.csv_row[x] }.uniq.count  < v.count
	    #}
	    first = true
	    v.map {|i|  
	      P6::Xml.xml(:tr) {
		classes = []
		if first
		  # First row of a set of Initiatives with the same ID is different - 
		  # The ID columns span the whole set:
		  # TODO - take this out of (above) the v.map loop, maybe
		  first = false
		  classes << "first"
		  id_headers.map { |h|
		    P6::Xml.xml(:td, :class => classes.join(" "), :rowspan => v.count) { "#{i.csv_row[h]}" }
		  }.join
		else
		  ""
		end +

		outlets_headers.map {|h|
		  value = i.csv_row[h]

		  # An array of values for column h of the CSV for each Initiative with the same duplicated id:
		  all_values = v.map { |j| j.csv_row[h] }

		  # Now select out of all_values just those values equal to the value
		  # of this column for Initiative i:
		  same_values = all_values.select{ |j| j == value }

		  # We want to colour the background of the cell depending on whether or not Initiative i
		  # has the same value in column h as any other Initiative with the same id as i.
		  # To find this out, we just count up the number of elments in same:
		  td_classes = classes + [same_values.count > 1 ? "common" : "different"]

		  #P6::Xml.xml(:td, :class => common.include?(h) ? "common" : "different") { "#{i.csv_row[h]}" }
		  P6::Xml.xml(:td, :class => td_classes.join(" ")) { "#{i.csv_row[h]}" }
		}.join
	      }
	    }.join("\n")
	  }.join("\n")
	}
      }
    }
  end
  def map_app_json(prog_ctr, postcode_lat_lng_cache)
    JSON.pretty_generate(
      {
	# The format matches that created by getdata_using_sparql.php:
	status: "success",
	data: map {|i|
	  res = postcode_lat_lng_cache.get(i.ospostcode_uri)
	  prog_ctr.step
	  if res
	    {
	      name: i.name,
	      uri: i.uri,
	      loc_uri: i.ospostcode_uri,
	      lat: res.lat.value,
	      lng: res.lng.value,
	      www: i.homepage
	    }
	  else
	    nil
	  end
	}.compact
      }
    )
  end
  def map_app_json_obsolete(prog_ctr)
    # Re-read previous results, so we don't have to do unnecessary queries:
    osres_file = "os_postcode_cache.json"
    failure_value = 0
    begin
      f = File.open(osres_file, "rb")
    rescue => e
      puts "Failed to read #{osres_file}"
      f = nil
    end
    osres = f ? JSON.parse(f.read) : {}
    #pp osres
    res = "[\n" +
      map {|i|
      prog_ctr.step

      begin
	r = osres[i.ospostcode_uri.to_s]
	#pp i.ospostcode_uri.to_s
	#pp r
	if (r == failure_value)
	  raise "#{osres_file} records error result"
	elsif (r)
	  source = "cache"
	  lat, lng = r
	else
	  source = "network"
	  graph = RDF::Graph.new
	  graph.load(i.ospostcode_uri)
	  #pp(graph)
	  query = RDF::Query.new({
	    :stuff => {
	      RDF::URI("http://www.w3.org/2000/01/rdf-schema#label") => :postcode,
	      RDF::URI("http://www.w3.org/2003/01/geo/wgs84_pos#lat") => :lat,
	      RDF::URI("http://www.w3.org/2003/01/geo/wgs84_pos#long") => :lng
	    }
	  })
	  res = query.execute(graph)
	  raise "No results from query" unless res.size == 1
	  raise "No lat from query" unless res[0][:lat]
	  lat = res[0][:lat]
	  raise "No lng from query" unless res[0][:lng]
	  lng = res[0][:lng]
	  osres[i.ospostcode_uri.to_s] = [lat, lng]
	  puts "#{$0}: from #{source} Postcode #{i.ospostcode_uri}:\tLatitude: #{lat}\tLongitude: #{lng}"
	end

	"{" +
	  {
	  name: i.name,
	  uri: i.uri,
	  loc_uri: i.ospostcode_uri,
	  lat: lat,
	  lng: lng,
	  www: i.homepage

	}.map{|k, v| "\"#{k}\": \"#{v}\""}.join(", ") +
	  "}"
      rescue => e
	$stderr.puts "Failed to load and read #{i.ospostcode_uri}, #{e.message}" unless source == "cache"
	osres[i.ospostcode_uri.to_s] = failure_value	# To save this error in the osres_file
	nil
      end
    }.compact.join(",\n") + "\n]\n"
      f.close if f
      File.open(osres_file, "w") {|f| f.write(JSON.pretty_generate(osres))}
      return res

  end
  def duplicate_ids
    ids = map{|i| i.id}
    ids.select{ |e| ids.count(e) > 1 }.uniq
  end
  def remove_duplicate_ids
    dup_ids = duplicate_ids
    if dup_ids.size > 0
      warning(["The dataset has the following duplicate ids:", dup_ids.join(", "), "Duplicates are being removed from the dataset. This may not be what you want!"])
    end
    #remove elements with duplicate ids
    uniq!{|e| e.id}
  end
  def create_files(postcode_lat_lng_cache)
    # TODO - haven't we alreay removed duplicates before this function is called? Where best to do it?
    remove_duplicate_ids
    prog_ctr = P6::ProgressCounter.new("Creating RDF, Turtle and HTML files for each initiative... ", size)
    each {|i|
      prog_ctr.step
      graph = i.make_graph
      begin
	rdf_filename = P6::RdfXml.save_file(dir: $options.output_dir, :basename => i.basename, :prefixes => $prefixes, :graph => graph)
	ttl_filename = P6::Turtle.save_file(dir: $options.output_dir, :basename => i.basename, :prefixes => $prefixes, :graph => graph)
	html_filename = P6::Html.save_file(html: i.html(rdf_filename, ttl_filename, html_fragment_for_link), dir: $options.output_dir, basename: i.basename)
      rescue => e
	$stderr.puts "Error [#{e.message}] saving \n#{i.csv_row}"
	$stderr.puts e.backtrace.join("\n")
      end
    }
    puts "Creating RDF, Turtle and HTML files for the collection as a whole..."
    graph = make_graph
    rdf_filename = P6::RdfXml.save_file(dir: $options.output_dir, :basename => Collection.basename, :prefixes => $prefixes, :graph => graph)
    ttl_filename = P6::Turtle.save_file(dir: $options.output_dir, :basename => Collection.basename, :prefixes => $prefixes, :graph => graph)
    html_filename = P6::Html.save_file(dir: $options.output_dir, basename: Collection.basename, html: html)
    html_filename = P6::Html.save_file(dir: $options.output_dir, basename: Collection.about_basename, html: about_html)

    prog_ctr = P6::ProgressCounter.new("Creating RDF/XML and Turtle for all initiatives in one big file (for upload to OntoWiki)... ", size)
    graph = RDF::Graph.new
    each {|i|
      prog_ctr.step
      graph = i.populate_graph(graph)
    }
    puts "Saving postcode_lat_lng_cache file..."
    postcode_lat_lng_cache.save_as_rdf(graph)
    puts "Saving one big RDF/XML file..."
    rdf_filename = P6::RdfXml.save_file(dir: $options.output_dir, :basename => Collection.one_big_file_basename, :prefixes => $prefixes, :graph => graph)
    puts "Saving one big Turtle file..."
    ttl_filename = P6::Turtle.save_file(dir: $options.output_dir, :basename => Collection.one_big_file_basename, :prefixes => $prefixes, :graph => graph)
  end
  def create_sparql_files
    File.open($options.map_app_sparql, "w") {|f|
      f.puts <<ENDSPARQL
PREFIX essglobal: <#{$essglobal.to_uri.to_s}>
PREFIX rdf: <#{RDF.to_uri.to_s}>
PREFIX gr: <#{RDF::Vocab::GR.to_uri.to_s}>
PREFIX foaf: <#{RDF::Vocab::FOAF.to_uri.to_s}>
PREFIX osspatialrelations: <#{$osspatialrelations.to_uri.to_s}>
PREFIX wgs84_pos: <http://www.w3.org/2003/01/geo/wgs84_pos#>
PREFIX : <#{uri}>
SELECT ?name ?uri ?loc_uri ?lat ?lng ?www
WHERE {
	?uri rdf:type essglobal:SSEInitiative .
	?uri gr:name ?name .
	?uri foaf:homepage ?www .
	?uri essglobal:hasAddress ?addr .
	?addr osspatialrelations:within ?loc_uri .
	?loc_uri wgs84_pos:lat ?lat.
	?loc_uri wgs84_pos:long ?lng.
}
LIMIT #{size}
ENDSPARQL
    }
  end
  private
  def uri
    RDF::URI("#{$options.uri_base}#{Collection.basename}")
  end
  def html_fragment_for_link
    P6::Xml.xml(:div) {
      P6::Xml.xml(:p) {
	"The URI for the whole list is: " +
	P6::Html.link_to(uri.to_s)
      }
    }
  end
end

class Initiative
  attr_reader :id, :name, :postcode_text, :postcode_normalized, :csv_row, :homepage 
  def self.from_outlet(csv_row)
    postcode_text = csv_row["Postcode"].upcase
    postcode_normalized = postcode_text.gsub(/\s+/, "")
    Initiative.new(csv_row, {
      name: csv_row["Outlet Name"],
      homepage: csv_row["Website"],
      postcode_text: postcode_text,
      postcode_normalized: postcode_normalized,
      # There may be many outlets with the same CUK Organisation ID, so we add the postcode to (hopefilly!) create a unique ID.
      # In fact, this leaves many duplicate IDs.
      # The Collection.duplicates_html method generates an HTML table which may be illuminating!

      # TODO - this ID is not good enough :-(
      id: csv_row["CUK Organisation ID"] + postcode_normalized
    })
  end
  def self.from_org(csv_row)
    postcode_text = csv_row["Registered Postcode"].upcase
    postcode_normalized = postcode_text.gsub(/\s+/, "")
    Initiative.new(csv_row, {
      name: csv_row["Trading Name"],
      homepage: nil,
      postcode_text: postcode_text,
      postcode_normalized: postcode_normalized,
      id: csv_row["CUK Organisation ID"]
    })
  end
  def initialize(csv_row, opts)
    @csv_row = csv_row
    @name = opts[:name] || ""
    @homepage = opts[:homepage] || ""
    @postcode_text = opts[:postcode_text] || ""
    @postcode_normalized = opts[:postcode_normalized] || ""
    @id = opts[:id] || ""
    if @id.empty?
      raise "Id is empty. " + source_as_str
    end
  end
  def source(fld)
    # Note that empty columns are assigned the empty string, instead of nil
    @csv_row[fld] || ""
  end
  def source_as_str
    @csv_row.to_s
  end

  def basename	# for output files
    # Unlike the bash command basename, this is the basename without the extension.
    # TODO - rename basename_without_ext ?
    "#{$options.dataset}/#{@id}"
  end
  def uri
    RDF::URI("#{$options.uri_base}#{basename}")
  end
  def address_uri
    # We don't really weant to have to mint URIs for the Address, but OntoWiki doesn't seem to
    # want to load the data inside blank URIs, so this is an experimental workaround:
    RDF::URI("#{$options.uri_base}#{basename}Address")
  end
  def turtle_url
    RDF::URI("#{$options.doc_url_base}#{basename}.ttl")
  end
  def html_url
    RDF::URI("#{$options.doc_url_base}#{basename}.html")
  end
  def rdf_url
    RDF::URI("#{$options.doc_url_base}#{basename}.rdf")
  end
  def html(rdf_filename, ttl_filename, collection_fragment)
    P6::Xml.xml(:html) {
      P6::Xml.xml(:head) {
	P6::Xml.xml(:title) { "Co-ops UK experimental dataset" } +
	$css_files_array.map {|f|
	  P6::Xml.xml(:link, rel: "stylesheet", type: "text/css", href: "../#{f}")
	}.join
      } +
      P6::Xml.xml(:body) {
	P6::Xml.xml(:h1) { name } +
	P6::Xml.xml(:p) { 
	  "This data is from an experimental dataset. See " + 
	  P6::Html.link_to(Collection.about_uri.to_s, " about this dataset") +
	  " for more information."
	} +
	collection_fragment +	# with link back to list of all.
	P6::Xml.xml(:h3) { "Contents" } +
	P6::Xml.xml(:ul) {
	  P6::Xml.xml(:li) { P6::Html.link_to("#table", @@heading[:table]) } +
	  P6::Xml.xml(:li) { P6::Html.link_to("#csv", @@heading[:csv]) } +
	  P6::Xml.xml(:li) { P6::Html.link_to("#rdf", @@heading[:rdf]) } +
	  P6::Xml.xml(:li) { P6::Html.link_to("#ttl", @@heading[:ttl]) }
	} + 
	P6::Xml.xml(:a, id: "table") + html_fragment_for_data_table +
	P6::Xml.xml(:a, id: "csv") + html_fragment_for_csv_row +
	P6::Xml.xml(:a, id: "rdf") + P6::Html.html_fragment_for_inserted_code(@@heading[:rdf], rdf_filename) +
	P6::Xml.xml(:a, id: "ttl") + P6::Html.html_fragment_for_inserted_code(@@heading[:ttl], ttl_filename)
      }
    }
  end
  @@heading = {
    table: "Summary of generated linked data",
    csv: "Original CSV data",
    rdf: "RDF document",
    ttl: "Turtle document"
  }
  def html_fragment_for_data_table
    P6::Xml.xml(:h2) { @@heading[:table] } +
      P6::Html.table(rows: [
	["Name", name],
	["URI for RDF and HTML", P6::Html.link_to(uri.to_s)],
	["URL for RDF/XML", P6::Html.link_to(rdf_url.to_s)],
	["URL for Turtle", P6::Html.link_to(turtle_url.to_s)],
	["URL for HTML", P6::Html.link_to(html_url.to_s)],
	["Website", P6::Html.link_to(homepage)],
	["Postcode", postcode_text],
	["Country", country_name],
	["postcode URI", ospostcode_uri ? P6::Html.link_to(ospostcode_uri.to_uri.to_s) : "none available"]
    ])
  end
  def html_fragment_for_csv_row
    P6::Xml.xml(:h2) { @@heading[:csv] } +
      P6::Html.table(rows: @csv_row.headers.map { |h| [  CGI.escapeHTML(h), CGI.escapeHTML(source(h)) ] })
  end
  def self.type_uri
    $essglobal["SSEInitiative"]
  end
  def country_name
    "UK"
  end
  def ospostcode_uri
    # Return an ordnance survey postcode URI
    # TODO - raise an exception if there's not postcode URI for this postcode (e.g. Northern Irish ones??)
    postcode = postcode_normalized
    raise "Empty postcode" if postcode.empty?
    $ospostcode[postcode]	# Convert it to RDF URI, using $ospostcode vocab.
  end
  def make_graph
    graph = RDF::Graph.new
    populate_graph(graph)
  end
  def populate_graph(graph)
    graph.insert([uri, RDF.type, Initiative.type_uri])
    graph.insert([uri, RDF::Vocab::GR.name, name])
    graph.insert([uri, RDF::Vocab::FOAF.homepage, homepage])
    graph.insert([uri, essglobal.hasAddress, make_address(graph)])
    # legal-form/L2 is a co-operative.
    # Is everything in the co-ops UK open dataset actually a co-operative?
    #graph.insert([uri, essglobal.legalForm, RDF::URI("http://www.purl.org/essglobal/standard/legal-form/L2")])
    graph.insert([uri, essglobal.legalForm, $essglobal_standard["legal-form/L2"]])

#    begin
#      postcode_uri = ospostcode_uri
#      geolocation = RDF::Node.new	# Blank node, as we have no lat/long information.
#      # The use of the solecon vocabulary is a temporary measure, until we figure out how to do this properly!
#      # It may be that we should be looking at something along the lines of the examples (section 1.5)
#      # presented at https://www.w3.org/2011/02/GeoSPARQL.pdf.
#      graph.insert([geolocation, RDF.type, $solecon.GeoLocation])
#      graph.insert([uri, $solecon.hasGeoLocation, geolocation])
#      graph.insert([geolocation, $solecon.within, postcode_uri])
#    rescue StandardError => e
#      warning([e.message, source_as_str])
#    end
    return graph
  end
  private
  def essglobal
    $essglobal
  end
  def make_address(graph)
    addr = $options.allow_blank_nodes ? RDF::Node.new : address_uri
    graph.insert([addr, RDF.type, essglobal["Address"]])
    graph.insert([addr, RDF::Vocab::VCARD["postal-code"], postcode_text])
    graph.insert([addr, RDF::Vocab::VCARD["country-name"], country_name])
    begin
      postcode_uri = ospostcode_uri
      # We can say that the addr is osspatialrelations.within the postcode_uri because:
      #     addr is an instance of geosparql:SpatialObject
      #     osspatialrelations.within is owl:equivalentProperty of geosparql:sfWithin
      #     geosparql:sfWithin has domain geosparql:SpatialObject
      #     In the above, geosparql is  <http://www.opengis.net/ont/geosparql>
      graph.insert([addr, $osspatialrelations.within, postcode_uri])
    rescue StandardError => e
      warning([e.message, source_as_str])
    end
    return addr
  end
end

# --------------------------------
# Here we load data from CSV files.
# --------------------------------
# For testing, we can load just a smaller set of test_rows from each CSV file (if short_test_run is true)
short_test_run = !!$options.max_csv_rows
test_rows = $options.max_csv_rows
collection = Collection.new

puts "Reading #{$options.outlets_csv}..."
rows_tested = 0;
CSV.foreach($options.outlets_csv, :encoding => "ISO-8859-1", :headers => true) do |row|
  begin
    # See comments below about encoding.
    row.headers.each {|h| row[h].encode!(Encoding::ASCII_8BIT) unless row[h].nil? }
    initiative = Initiative.from_outlet(row)
    collection << initiative
  rescue StandardError => e # includes ArgumentError, RuntimeError, and many others.
    warning(["Could not create Initiative from CSV [$options.outlets_csv]: #{e.message}", "The following row from the CSV data will be ignored:", row.to_s])
  end

  # For rapidly testing on subset:
  if short_test_run
    rows_tested += 1
    break if rows_tested > test_rows
  end
end

puts "Reading #{$options.orgs_csv}..."
rows_tested = 0;
CSV.foreach($options.orgs_csv, :encoding => "ISO-8859-1", :headers => true) do |row|
  begin
    # Change encoding! This is a workaround for a problem that emerged when processing the orgs_csv file.
    row.headers.each {|h| row[h].encode!(Encoding::ASCII_8BIT) unless row[h].nil? }
    # Why does it not work with UTF-8? 
    #row.headers.each {|h| row[h].encode!(Encoding::UTF_8) unless row[h].nil? }
    initiative = Initiative.from_org(row)
    collection << initiative
  rescue StandardError => e # includes ArgumentError, RuntimeError, and many others.
    warning(["Could not create Initiative from CSV [$options.orgs_csv]: #{e.message}", "The following row from the CSV data will be ignored:", row.to_s])
  end

  # For rapidly testing on subset:
  if short_test_run
    rows_tested += 1
    break if rows_tested > test_rows
  end
end
# -------------------------------------------------------------------------
# From this point on, we control exactly what is generated from this script.
# -------------------------------------------------------------------------

if $options.check_websites
  # Generating the websites.html is expensive - each URL is accessed to check it's HTTP response code.
  website_html_file = "websites.html"
  prog_ctr = P6::ProgressCounter.new("Saving table of websites to #{website_html_file} ... ", collection.size)
  P6::Html.save_file(html: collection.websites_html(prog_ctr), filename: website_html_file)
end

# Generate a report about diplicate IDs:
dups_html_file = "duplicates.html"
puts "Saving table of duplicates to #{dups_html_file} ..."
P6::Html.save_file(html: collection.duplicates_html, filename: dups_html_file)

# From here on, we're working with the collection after having duplicate IDs removed:
collection.remove_duplicate_ids
postcode_lat_lng_cache = RdfCache.new("postcode_lat_lng.json", {
    lat: "http://www.w3.org/2003/01/geo/wgs84_pos#lat",
    lng: "http://www.w3.org/2003/01/geo/wgs84_pos#long"
  })

# TODO - should this be moved to create_files?
# Generate a json file that can be used by the map-app, as an alternative to loading the data from, for example, a sparkle endpoint.
map_app_json_file = "initiatives.json"
prog_ctr = P6::ProgressCounter.new("Saving map-app data to #{map_app_json_file} ... ", collection.size)
P6::File.save(collection.map_app_json(prog_ctr, postcode_lat_lng_cache), map_app_json_file)

#collection.resolve_duplicates
collection.create_files(postcode_lat_lng_cache)
collection.create_sparql_files

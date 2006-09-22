class ActiveRecord::Base
  # Inside an ActiveRecord model definition,
  #
  #   define_finder query_name, query_type, options_hash
  #
  # will create a SQL query method called +query_name+ from a given
  # +options_hash+. +query_type+ can be :first or :all.
  #
  # The plugin supports all standard options except :include, but ignores
  # with_scope options. In addition, the :piggy option of the piggy_back
  # plugin can be used.
  #
  # Example:
  #
  #   class Recipe
  #     define_finder :find_all_of_user, :all,
  #                        :conditions => 'user = :user AND priv < :priv'
  #   end
  #
  # This defines a query method which can be called like so:
  #
  #   Recipe.find_all_of_user :user => 'martin', :priv => 1
  #
  # This call is equivalent to
  #
  #   Recipe.find :all, :conditions =>
  #            ['user = :user AND priv < :priv', {:user => 'martin', :priv => 1}]
  #
  # If options[:positional] is not +nil+ or +false+, the created query
  # method will use positional paramaters instead of a hash. In this case,
  # arguments are created in the order of appearance on the parameters
  # passed to define_finder. Therefore
  #
  #    define_finder :find_all_of_user, :all,
  #                  :conditions => 'user = :user AND priv < :priv',
  #                  :positional => true
  #
  # will create a query method with parameters +user+ and +priv+, which can be
  # called like so:
  #
  #     Recipes.find_all_of_user('martin', 1)
  #
  def self.define_finder(query_name, query_type, options)
    QueryBuilder.new(connection, self).define_query(query_name, query_type, options)
  end

  class QueryBuilder
    def initialize(connection, klass)
      @klass = klass
      @query = ""
      @params = []
      @connection = connection
    end

    def define_query(query_name, query_type, options)
      options[:limit] = '1' if query_type == :first
      build_query options
      unless @params.empty?
        if options[:positional]
          params = "(#{@params.map{|name| name[1..-1]}.join(', ')})"
        else
          params = "(params)"
        end
      end
      @klass.class_eval <<-"end_eval"
         def self.#{query_name}#{params}
           connection = self.connection
           find_by_sql("#{@query}")#{".first" if query_type == :first}
         end
      end_eval
    end

    private
    def build_query(options)
      @klass.send(:add_piggy_back!, options) if @klass.respond_to? :piggy_pack!
      add_select(options)
      add_from(options)
      add_joins(options)
      add_conditions(options)
      add_group(options)
      add_order(options)
      add_limit(options)
    end

    def add_select(options)
      @query << "SELECT #{options[:select] || '*'} "
    end

    def add_from(options)
      @query << "FROM #{options[:from] || @klass.table_name} "
    end

    def add_joins(options)
      @query << " #{options[:joins]} " if options[:joins]
    end

    def add_conditions(options)
      conditions = options[:conditions]
      add_params!(conditions, options) if conditions
      segments = []
      segments << conditions if conditions
      segments << @klass.type_condition unless @klass.descends_from_active_record?
      @query << "WHERE (#{segments.join(") AND (")}) " unless segments.empty?
    end

    def add_group(options)
      if options[:group]
        add_params!(options[:group], options)
        @query << " GROUP BY #{options[:group]} "
      end
    end

    def add_order(options)
      if options[:order]
        add_params!(options[:order], options)
        @query << " ORDER BY #{options[:order]}"
      end
    end

    def add_limit(options)
      add_params!(options[:limit], options)  if options[:limit]
      add_params!(options[:offset], options) if options[:offset]
      @connection.add_limit_offset!(@query, options)
    end

    def add_params!(sql, options)
      sql.gsub!(/(:\w+)/) do
        @params << $1 unless @params.include? $1
        if options[:positional]
          '#{connection.quote ' + $1[1..-1] + '}'
        else
          '#{connection.quote params[' + $1 +']}'
        end
      end
    end
  end
end

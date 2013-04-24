# encoding: utf-8

require 'publishable/railtie' if defined?(Rails)
require 'workflow'

# Allows a given boolean, date, or datetime column to indicate whether a model object is published.
# Boolean published column just is an on/off flag.
# Date/datetime column requires value of published column to be before "now" for the object to be published.
# Specify the column name via the :on option (defaults to :published) and make sure to create the column
# in your migrations.
#
# Provides scopes for finding published and unpublished items, and (for date/datetime published columns) for returning
# recent or upcoming items.
#
# @author Martin Linkhorst <m.linkhorst@googlemail.com>
# @author David Daniell / тιηуηυмвєяѕ <info@tinynumbers.com>
module Publishable

  # Add our features to the base class.
  # @see ClassMethods#publishable
  # @param [Object] base
  def self.extended(base)
    base.extend ClassMethods
  end

  # Define scopes and methods for querying and manipulating Publishables.
  module ClassMethods
    include Workflow
    # DSL method to link this behavior into your model.  In your ActiveRecord model class, add +publishable+ to include
    # the scopes and methods for publishable objects.
    #
    # @example
    #   class Post < ActiveRecord::Base
    #     publishable
    #   end
    #
    # @param [Hash] options The publishable options.
    # @option options [String, Symbol] :on (:publishable) The name of the publishable column on the model.
    def publishable(options = {})
      return unless table_exists?

      publish_type = (options[:type] || :datetime)
      column_name = nil;
      column_start_name = nil;
      column_end_name = nil;

      #Obtain columns name and check consistency between publish type and column type
      case publish_type
        when :date, :datetime
          column_start_name = (options[:start] || :publish_start).to_sym
          column_end_name = (options[:end] || :publish_end).to_sym

          unless self.columns_hash[column_start_name.to_s].present? and self.columns_hash[column_end_name.to_s].present?
            raise ActiveRecord::ConfigurationError, "No '#{column_start_name}'column available for Publishable column on model #{self.name}"
          end

          column_start_type = self.columns_hash[column_start_name.to_s].type
          column_end_type = self.columns_hash[column_end_name.to_s].type

          #Raise a error case publish type and column_type not equals
          unless column_start_type == publish_type 
            raise ActiveRecord::ConfigurationError, "The '#{column_start_name}'column not equals declared type publish on model #{self.name}"
          end
          unless column_end_type == publish_type 
            raise ActiveRecord::ConfigurationError, "The '#{column_end_name}'column not equals declared type publish on model #{self.name}"
          end
        when :boolean
          column_name = (options[:on] || :published).to_sym
          column_type = self.columns_hash[column_name.to_s].type

          #Raise a error case publish type and column_type not equals
          unless column_type == publish_type 
            raise ActiveRecord::ConfigurationError, "The '#{column_name}'column not equals declared type publish on model #{self.name}"
          end
          unless self.columns_hash[column_name.to_s].present? and self.columns_hash[column_name.to_s].present?
            raise ActiveRecord::ConfigurationError, "No '#{column_name}'column available for Publishable column on model #{self.name}"
          end
        else
          raise ActiveRecord::ConfigurationError, "Invalid publish_type #{publish_type} for Publishable column on model #{self.name}"
      end

      

      if respond_to?(:scope)

        # define published/unpublished scope
        case publish_type
          when :date,:datetime
            scope :published, lambda { |*args|
              start_date = args[0] || Date.current
              end_date = args[1]

              where(arel_table[column_start_name].not_eq(nil)).where(arel_table[column_start_name].lteq(start_date))
                .where(arel_table[column_end_name].eq(nil).or(arel_table[column_end_name].gteq(end_date)))
            }

            scope :unpublished, lambda { |*args|
              start_date = args[0] || Date.current
              end_date = args[1]
              where(arel_table[column_start_name].gt(start_date).or(arel_table[column_end_name].lt(end_date)))
            }

          when :boolean
            scope :published, lambda {
              where(column_name => true)
            }

            scope :unpublished, lambda {
              where(column_name => false)
            }

          else
            raise ActiveRecord::ConfigurationError, "Invalid column_type #{publish_type} for Publishable column on model #{self.name}"
        end

        # define recent/upcoming scopes
        if [:date, :datetime].include? publish_type
          scope :recent, lambda { |*args|
            how_many = args[0] || nil
            col_name = arel_table[column_start_name].name
            published.limit(how_many).order("#{col_name} DESC")
          }
          scope :upcoming, lambda { |*args|
            how_many = args[0] || nil
            col_name = arel_table[column_start_name].name
            unpublished.limit(how_many).order("#{col_name} ASC")
          }
        end

      end

      case publish_type
        when :date, :datetime
          class_eval <<-EVIL, __FILE__, __LINE__ + 1
            def published?(_when = DateTime.now)
              if('#{publish_type}'.to_sym == :date) 
                _when = _when.to_date
              end
              #{column_start_name} ? #{column_start_name} <= _when && 
                ( #{column_end_name} ? #{column_end_name} >= _when : true) : false
            end

            def unpublished?(_when = DateTime.now)
              !published?(_when)
            end

            def publish(_when_start = DateTime.now, _when_end = nil)
              if('#{publish_type}'.to_sym == :date) 
                _when_start = _when_start.to_date
              end

              unless published?(_when_start)
                self.#{column_start_name} = _when_start
                self.#{column_end_name} = _when_end

                puts self.#{column_start_name}
              end
            end

            def publish!(_when_start = DateTime.now, _when_end = nil)
              publish(_when_start, _when_end) && (!respond_to?(:save) || save)
            end

            def unpublish()
              self.#{column_start_name} = null
              self.#{column_end_name} = null
            end

            def unpublish!()
              unpublish() && (!respond_to?(:save) || save)
            end
          EVIL
        
        when :boolean
          class_eval <<-EVIL, __FILE__, __LINE__ + 1
            def published?()
              #{column_name}
            end

            def unpublished?()
              !published?()
            end

            def publish()
              self.#{column_name} = true
            end

            def publish!()
              publish()
              save if respond_to?(:save)
            end

            def unpublish()
              self.#{column_name} = false
            end

            def unpublish!()
              unpublish()
              save if respond_to?(:save)
            end
          EVIL

        else
          raise ActiveRecord::ConfigurationError, "Invalid column_type #{publish_type} for Publishable column on model #{self.name}"
      end

    end

    # @!group Query scopes added to publishable models

    # @!method published
    #   Query scope added to publishables that can be used to find published records. For Date/DateTime publishables,
    #   you can pass a specific date on which the results should be published.
    #   @example Find only records that are currently published
    #     published_posts = Post.published
    #   @example Find only records that will be published in two days
    #     future_posts = Post.published(Date.current + 2.days)
    #   @param [Date, Time, nil] when Specify a date/time for Date/DateTime publishables - defaults to the current date/time
    #   @!scope class

    # @!method unpublished
    #   Query scope added to publishables that can be used find records which are not published. For Date/DateTime
    #   publishables, you can pass a specific date on which the results should not have been published.
    #   @example Find only records that are not currently published
    #     unpublished_posts = Post.unpublished
    #   @param [Date, Time, nil] when Specify a date/time for Date/DateTime publishables - defaults to the current date/time
    #   @!scope class

    # @!method recent
    #   Query scope added to publishables that can be used to lookup records which are currently published. The results
    #   are returned in descending order based on the published date/time.
    #   @example Get the 10 most recently-published records
    #     recent_posts = Post.recent(10)
    #   @param [Integer, nil] how_many Specify how many records to return
    #   @!scope class

    # @!method upcoming
    #   Query scope added to publishables that can be used to lookup records which are not currently published. The
    #   results are returned in ascending order based on the published date/time.
    #   @example Get all posts that will be published in the future
    #     upcoming_posts = Post.upcoming
    #   @param [Integer, nil] how_many Specify how many records to return
    #   @!scope class

    # @!endgroup

    # @!group Instance methods added to publishable models

    # @!method published?
    #   Is this object published?
    #   @param [Date, Time, nil] when For Date/DateTime publishables, a date/time can be passed to determine if the
    #     object was / will be published on the given date.
    #   @return [Boolean] true if published, false if not published.
    #   @!scope instance

    # @!method unpublished?
    #   Is this object not published?
    #   @param [Date, Time, nil] when For Date/DateTime publishables, a date/time can be passed to determine if the
    #     object was not / will not be published on the given date.
    #   @return [Boolean] false if published, true if not published.
    #   @!scope instance

    # @!method publish
    #   Publish this object.  For a Boolean publish field, the field is set to true; for a Date/DateTime field, the
    #   field is set to the given Date/Time or to the current date/time.
    #   @param [Date, Time, nil] when For Date/DateTime publishables, a date/time can be passed to specify when the
    #     record will be published. Defaults to +Date.current+ or +Time.now+.
    #   @!scope instance

    # @!method publish!
    #   Publish this object, then immediately save it to the database.
    #   @param [Date, Time, nil] when
    #   @!scope instance

    # @!method unpublish
    #   Un-publish this object, i.e. set it to not be published.  For a Boolean publish field, the field is set to
    #   false; for a Date/DateTime field, the field is set to null.
    #   @!scope instance

    # @!method unpublish!
    #   Un-publish this object, then immediately save it to the database.
    #   @!scope instance

    # @!endgroup

  end
end

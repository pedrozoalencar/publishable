# encoding: utf-8

require 'publishable/railtie' if defined?(Rails)

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
module PublishedByPeriod
  # Add our features to the base class.
  # @see ClassMethods#publishable
  # @param [Object] base
  def self.extended(base)
    base.extend ClassMethods
  end

  # Define scopes and methods for querying and manipulating Publishables.
  module ClassMethods
    
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
    def published_by_period(options = {})
      return unless table_exists?

      column_start_name = (options[:start] || :publish_start).to_sym
      column_end_name = (options[:end] || :publish_end).to_sym

      unless self.columns_hash[column_start_name.to_s].present? and self.columns_hash[column_end_name.to_s].present?
        raise ActiveRecord::ConfigurationError, "No '#{column_start_name}'column available for PublishedByPeriod column on model #{self.name}"
      end

      if respond_to?(:scope)
        # define published/unpublished scope
        scope :in_published_period, lambda { |*args|
          start_date = args[0] || Date.current
          end_date = args[1]

          where(arel_table[column_start_name].not_eq(nil)).where(arel_table[column_start_name].lteq(start_date))
            .where(arel_table[column_end_name].eq(nil).or(arel_table[column_end_name].gteq(end_date)))
        }

        scope :out_published_period, lambda { |*args|
          start_date = args[0] || Date.current
          end_date = args[1]
          where(arel_table[column_start_name].gt(start_date).or(arel_table[column_end_name].lt(end_date)))
        }
      end

      class_eval <<-RUBY, __FILE__, __LINE__ + 1
        def in_published_period?(_when = DateTime.now)
          #{column_start_name} ? #{column_start_name} <= _when && 
            ( #{column_end_name} ? #{column_end_name} >= _when : true) : false
        end

        def out_published_period?(_when = DateTime.now)
          !published?(_when)
        end

        def publish_by_period(_when_start = DateTime.now, _when_end = nil)
          unless published?(_when_start)
            self.#{column_start_name} = _when_start
            self.#{column_end_name} = _when_end
          end
        end

        def publish_by_period!(_when_start = DateTime.now, _when_end = nil)
          publish_by_period(_when_start, _when_end) && (!respond_to?(:save) || save)
        end
      RUBY
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

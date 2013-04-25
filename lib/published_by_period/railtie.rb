require 'rails/railtie'

module PublishedByPeriod

  # Extend ActiveRecord::Base to enable the +publishable+ DSL.
  class Railtie < Rails::Railtie
    initializer 'publishable.initialize' do |app|
      ActiveRecord::Base.extend Publishable::ClassMethods
    end
  end
end
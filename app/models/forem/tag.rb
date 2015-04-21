module Forem
  class Tag < ActiveRecord::Base
    has_many :topic_tags
    has_many :topics, through: :topic_tags

    def to_s
      tag
    end
  end
end

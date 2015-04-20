class AddTagsToTopics < ActiveRecord::Migration
  def change
    add_column :forem_topics, :tags, :text, array: true, default: []
  end
end

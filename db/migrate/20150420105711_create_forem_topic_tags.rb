class CreateForemTopicTags < ActiveRecord::Migration
  def change
    create_table :forem_topic_tags do |t|
      t.references :topic
      t.references :tag
    end
    add_index :forem_topic_tags, :topic_id
    add_index :forem_topic_tags, :tag_id
  end
end

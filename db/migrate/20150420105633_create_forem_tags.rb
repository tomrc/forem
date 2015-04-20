class CreateForemTags < ActiveRecord::Migration
  def change
    create_table :forem_tags do |t|
      t.string :name
    end
  end
end

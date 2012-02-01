class Initial < ActiveRecord::Migration
  def self.up
    create_table :dmfollow do |t|
      t.string :lft, null: false
      t.string :rgt, null: false
      t.integer :lft_id, null: false
      t.integer :rgt_id, null: false

      t.timestamps
    end
    add_index :dmfollow, :lft_id
    add_index :dmfollow, :rgt_id
  end

  def self.down
    raise ActiveRecord::IrreversibleMigration
  end
end

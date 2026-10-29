class CreateMasterProducts < ActiveRecord::Migration[7.2]
  def change
    create_table :master_products do |t|
      t.string  :sku,  null: false
      t.string  :name, null: false
      t.decimal :price, precision: 10, scale: 2, null: false
      t.datetime :synced_at

      t.timestamps
    end

    add_index :master_products, :sku, unique: true
  end
end

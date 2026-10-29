class CreateShopProducts < ActiveRecord::Migration[7.2]
  def change
    create_table :shop_products do |t|
      t.references :shop,           null: false, foreign_key: true
      t.references :master_product, null: true,  foreign_key: true
      t.string  :name,  null: false
      t.decimal :price, precision: 10, scale: 2, null: false

      t.timestamps
    end

    add_index :shop_products, [:shop_id, :master_product_id]
  end
end

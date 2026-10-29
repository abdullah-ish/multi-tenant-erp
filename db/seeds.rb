require "csv"

puts "== Seeding Host DB =="

acme   = Company.find_or_create_by!(slug: "acme")   { |c| c.name = "Acme Corp" }
globex = Company.find_or_create_by!(slug: "globex") { |c| c.name = "Globex Inc" }

puts "Created companies: #{[ acme.slug, globex.slug ].join(', ')}"

[ acme, globex ].each do |company|
  puts "\n== Provisioning tenant: #{company.slug} =="
  TenantConnection.provision!(company.slug)

  TenantConnection.switch(company.slug) do
    user = User.find_or_create_by!(email: "admin@#{company.slug}.com") do |u|
      u.password = "password123"
      u.password_confirmation = "password123"
    end
    puts "  User: #{user.email}"

    shop = Shop.find_or_create_by!(name: "#{company.name} Main Shop")
    puts "  Shop: #{shop.name}"

    csv_path = Rails.root.join("db/csv/#{company.slug}_products.csv").to_s
    ProductSyncJob.perform_now(company.slug, csv_path)
    puts "  Synced products from #{csv_path}"

    master_products = MasterProduct.all.to_a
    master_products.each do |mp|
      ShopProduct.find_or_create_by!(shop: shop, master_product: mp) do |sp|
        sp.name  = mp.name
        sp.price = mp.price
      end
    end
    puts "  Created #{master_products.size} shop products"

    shop_products = ShopProduct.limit(2).to_a
    order = Order.new(shop: shop, user: user, status: "pending", total: 0)
    items_total = 0
    shop_products.each do |sp|
      order.order_items.build(shop_product: sp, quantity: 1, unit_price: sp.price)
      items_total += sp.price
    end
    order.total = items_total

    # Skip reporting callback so seeds do not dispatch background jobs
    Order.skip_callback(:commit, :after, :enqueue_report_job)
    order.save!
    Order.set_callback(:commit, :after, :enqueue_report_job)

    puts "  Created sample order ##{order.id} total=#{order.total}"
  end
end

puts "\n== Seeding complete =="

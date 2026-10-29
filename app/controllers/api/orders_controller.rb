module Api
  class OrdersController < BaseController
    def create
      shop = Shop.find(order_params[:shop_id])

      order = Order.new(
        shop:   shop,
        user:   Current.user,
        status: "pending",
        total:  0
      )

      items_total = 0

      order_params[:items].each do |item_params|
        shop_product = ShopProduct.find(item_params[:shop_product_id])
        quantity     = item_params[:quantity].to_i
        unit_price   = shop_product.price

        order.order_items.build(
          shop_product: shop_product,
          quantity:     quantity,
          unit_price:   unit_price
        )

        items_total += quantity * unit_price
      end

      order.total = items_total

      if order.save
        render json: { order_id: order.id, status: order.status, total: order.total }, status: :created
      else
        render json: { errors: order.errors.full_messages }, status: :unprocessable_entity
      end
    end

    private

    def order_params
      params.require(:order).permit(
        :shop_id,
        items: [ :shop_product_id, :quantity ]
      )
    end
  end
end

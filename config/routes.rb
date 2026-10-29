Rails.application.routes.draw do
  namespace :api do
    post "login",  to: "sessions#create"
    post "orders", to: "orders#create"
  end

  get "up" => "rails/health#show", as: :rails_health_check
end

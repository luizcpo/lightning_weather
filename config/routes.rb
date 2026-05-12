Rails.application.routes.draw do
  mount RailsIcons::Engine, at: '/rails_icons'
  get "up" => "rails/health#show", as: :rails_health_check

  resource :forecast, only: %i[show], controller: "forecasts"

  root "forecasts#show"
end

Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  resource :forecast, only: %i[show], controller: "forecasts"

  root "forecasts#show"
end

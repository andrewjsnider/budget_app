Rails.application.routes.draw do
  root to: "dashboard#show"

  resources :accounts, except: [:destroy] do
    member do
      get  :starting_balance
      post :create_starting_balance
    end

    resources :reconciliations, only: [:new, :create, :show]
  end

  get  "budget/:month", to: "budget_months#show",   as: :budget_month
  patch "budget/:month", to: "budget_months#update"
  get  "budget", to: "budget_months#index", as: :budget

  resources :categories

  resources :income_sources, except: [:destroy] do
    resources :income_estimates, except: [:destroy]
  end

  resources :recurring_expenses, except: [:destroy]

  get "reports/projection/:account_id", to: "reports/projections#show", as: :reports_projection
  get "reports/utilities", to: "reports/utilities#index", as: :reports_utilities

  resource :session
  resources :passwords, param: :token

  resources :transactions, except: [:show]

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
end

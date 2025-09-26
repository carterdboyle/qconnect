Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  mount ActionCable.server => "/cable"

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
  root "home#terminal"

  get "/v1/csrf", to: "csrf#show"
  
  scope "/v1" do
    get "session", to: "sessions#show" #whoami
    delete "session", to: "sessions#destroy" #logout
  end

  scope "/v1/register" do
    post "init", to: "register#init"
    post "verify", to: "register#verify"
  end

  scope "/v1/login" do
    post "challenge", to: "login#challenge"
    post "submit", to: "login#submit"
  end

  scope "/v1/contacts" do
    # requests
    post "requests", to: "contact_requests#create" #send
    get "requests", to: "contact_requests#index" #list pending
    post "requests/:id/respond", to: "contact_requests#respond" #accept/decline

    # address book
    get "", to: "contacts#index" # my contacts
    get ":handle", to: "contacts#show" # one contact by handle
  end

  scope "/v1" do
    resources :messages, only: [ :index, :create ]
  end

  scope "/v1/chats" do
    post "open", to: "chats#open"
    get "summary", to: "chats#summary"
    post ":id/read", to: "chats#read"
    get ":id/messages", to: "chats#messages_since"
    get ":id/last_read", to: "chats#last_read"
  end
end

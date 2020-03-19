# frozen_string_literal: true

require "slim"
require "sinatra"
require "sqlite3"
require "bcrypt"
require "securerandom"

require_relative "./model.rb"

enable :sessions

development = true
require "sinatra/reloader" if development
also_reload "./model.rb"
also_reload "./app.rb"

# for cookies
require "rack/contrib"
require "sinatra/cookies"
use Rack::Cookies
helpers Sinatra::Cookies

# look into this later
require "rack/protection"
use Rack::Protection

# https://github.com/kickstarter/rack-attack needs to be configured
# require "rack/attack"
# use Rack::Attack
# Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

# Rack::Attack.throttle("requests by ip", limit: 5, period: 2) do |request|
#   request.ip
# end

# require "sinatra/rate-limiter"
# enable :rate_limiter

# for mail
require "mail"

require "parseconfig"
config = ParseConfig.new("./config.properties")

Mail.defaults do
  delivery_method :smtp, {
    address: config["email_server"],
    port: 465,
    user_name: config["email_user"],
    password: config["email_password"],
    authentication: :login,
    ssl: true,
    openssl_verify_mode: "none"
  }
end

before do
  if !development
    session[:login] = "$2a$12$Wr1G1Y7elWcsdBPGJeUq0ut3AMsZZ/58jqhsC6Uxx2cz2Wn/wsMOS"
    session[:name] = "hej"
    session[:role] = "member"
  else
    # rate_limit
  end

  session[:error] = nil if request.post?

  if request.path_info != "/" && !request.path_info.start_with?("/user/") && session[:login].nil?
    redirect("/")
  end
end

get("/") do
  if session[:login].nil?
    if !request.cookies["remember_me"].nil? && request.cookies["remember_me"] != ""
      session[:login] = request.cookies["remember_me"]
      session[:name] = "test"
      session[:role] = "member"
      redirect("/files/show")
    end
    # Not logged in redirects to the startpage
    slim(:start, locals: {error: session[:error]})
  else
    redirect("/files/show")
  end
end

get("/files/show") do
  file_ids = get_file_ids(session[:login])
  files = get_all_files(file_ids)
  slim(:"files/show", locals: {error: session[:error], name: session[:name], files: files[:files], public_files: files[:public_files]})
end

get("/private/files/:user_id/:file_name") do
  if params[:user_id].to_i == get_user_id(session[:login])
    send_file("./private/files/#{params[:user_id]}/#{params[:file_name]}")
  else
    halt 403, "Access Denied, logged in as #{get_user_id(session[:login])} expected #{params[:user_id]}"
  end
end

get("/user/confirm_email/:key") do
  if session[:confirm_email] == params[:key] && !session[:login].nil?
    email_confirm(session[:login])
    session[:confirm_email] = nil
    redirect("/files/show")
  else
    "Wrong email or link, lol\nGo home: http://#{request.host_with_port}"
  end
end

post("/files/create") do
  result = file_upload(session[:login], params[:file], params[:public])
  if (result.is_a? String) && result.start_with?("ERROR: ")
    session[:error] = result
  end
  redirect("/files/show")
end

post("/files/delete") do
  file_id = params[:file_id]
  result = delete_file(file_id, session[:login]) == "error"

  if (result.is_a? String) && result.start_with?("ERROR: ")
    session[:error] = result
  end
  redirect("/files/show")
end

post("/user/register") do
  digest = user_register(params[:password], params[:name], params[:email])

  if digest.start_with?("ERROR: ")
    session[:error] = digest[7..-1]
    redirect("/")
  else
    session[:login] = digest
  end

  confirm_email_key = SecureRandom.urlsafe_base64
  session[:confirm_email] = confirm_email_key

  Mail.new(
    to: params[:email].to_s,
    from: "nasirforpresident2020@national.shitposting.agency",
    subject: "Confirm your account at epic cloud site",
    body: "Welcome to OUR site #{params[:name]}, where we steal you're data and sell it for profit\nSounds good?\nClick here to erase your suffering (by reading this mail you accept all our terms and conditions)\nhttp://#{request.host_with_port}/user/confirm_email/#{confirm_email_key}\n\nThanks for all the fish!"
  ).deliver

  session[:name] = params[:name]
  session[:role] = "member"
  redirect("/")
end

post("/user/login") do
  password = params[:password]
  name = params[:name]
  remember_password = params[:remember]
  user_info = user_login(password, name)
  if user_info[:password_correct]
    if remember_password
      response.set_cookie("remember_me",
        value: user_info["password_digest"],
        expires: Time.now + 2_592_000, # One month from today
        path: "/")
    end
    session[:login] = user_info[:password_digest]
    session[:name] = name
    session[:role] = user_info[:role] == "admin" ? "admin" : "member"
  else
    # Maybe change
    session[:error] = "incorrect login"
  end
  redirect("/")
end

post("/user/logout") do
  session.clear
  redirect("/")
end

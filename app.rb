# frozen_string_literal: true

require "slim"
require "sinatra"
require "sqlite3"
require "bcrypt"
require "securerandom"

require_relative "./model.rb"
include Model

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

# protects against general attacks
require "rack/protection"
use Rack::Protection

# used to stop bad behaving clients
require "active_support/cache"
require "rack/attack"
use Rack::Attack
Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

# Emails is slow to send so I want to throttle it as hard as possible
Rack::Attack.throttle("emails", limit: 5, period: 60.seconds) do |req|
  if (req.path == "/user/login" || req.path == "/user/resend_email") && req.post?
    req.ip
  end
end

Rack::Attack.throttle("register/ip", limit: 3, period: 30.seconds) do |req|
  if req.path == "/user/register" && req.post?
    req.ip
  end
end

Rack::Attack.throttle("requests/ip", limit: 100, period: 3.minutes) do |req|
  req.ip
end

Rack::Attack.throttle("post-requests/ip", limit: 100, period: 10.minutes) do |req|
  # post request require more processing server side → harder restrictions
  if req.post?
    req.ip
  end
end

Rack::Attack.throttled_response = lambda do |env|
  [429, {}, ["Sluta spamma sidan tack, vänta lite så kan du försöka igen senare"]]
end

# for mail
require "mail"
require "parseconfig"
config = ParseConfig.new("./config.properties")

before do
  session[:error] = nil if request.post?

  if request.path_info != "/" && !request.path_info.start_with?("/user/") && session[:login].nil?
    redirect("/")
  end
end

# Show landing page if not logged in, otherwise redirect to show files.
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

# Displays all Files.
#
# @see Model#get_file_ids
# @see Model#get_all_files
get("/files/show") do
  file_ids = get_file_ids(session[:login])
  files = get_all_files(file_ids)
  email = email_status(session[:login])
  slim(:"files/show", locals: {error: session[:error], name: session[:name], files: files[:files], public_files: files[:public_files], email: email})
end

# Displays a single file to edit.
#
# @param [Integer] file_id, the id of the file
# @see Model#get_all_files
get("/files/:file_id/edit") do
  files = get_all_files(params[:file_id])
  slim(:"files/edit", locals: {error: session[:error], name: session[:name], files: files[:files]})
end

# Download a private file.
#
# @param [Integer] :user_id, the id of the user
# @param [Integer] :file_name, the name of the file
get("/private/files/:user_id/:file_name") do
  result = user_can_access_private_file(session[:login], params[:user_id], params[:file_name])

  if result == true
    send_file("./private/files/#{params[:user_id]}/#{params[:file_name]}")
  elsif (result.is_a? String) && result.start_with?("ERROR: ")
    session[:error] = result
    redirect back
  end
end

# Confirms the email address and check if the provided key equals the correct key for that email address.
#
# @param [Integer] key, the key provided by the user
# @param [Integer] confirm_email, the key provided by the server
get("/user/confirm_email/:key") do
  if session[:confirm_email] == params[:key] && !session[:login].nil?
    email_confirm(session[:login])
    session[:confirm_email] = nil
    redirect("/files/show")
  else
    "Wrong email or link, lol\nGo home: http://#{request.host_with_port}"
  end
end

# Upload a file to the server.
#
# @see Model#file_upload
post("/files/create") do
  result = file_upload(session[:login], params[:file], params[:public])
  if (result.is_a? String) && result.start_with?("ERROR: ")
    session[:error] = result
  end
  redirect("/files/show")
end

# Delete a file from the server.
#
# @see Model#delete_file
post("/files/delete") do
  file_id = params[:file_id]
  result = delete_file(file_id, session[:login]) == "error"

  if (result.is_a? String) && result.start_with?("ERROR: ")
    session[:error] = result
  end
  redirect("/files/show")
end

# Delete a category.
#
# @see Model#delete_category
post("/categories/delete") do
  result = delete_category(session[:login], params[:file_id], params[:category].to_s)
  if (result.is_a? String) && result.start_with?("ERROR: ")
    session[:error] = result
  end
  redirect back
end

# Add a category.
#
# @see Model#add_category
post("/categories/add") do
  result = add_category(session[:login], params[:file_id], params[:category].to_s)
  if (result.is_a? String) && result.start_with?("ERROR: ")
    session[:error] = result
  end
  redirect back
end

# Delete a user from a file.
#
# @see Model#delete_user
post("/user/delete") do
  result = delete_user(session[:login], params[:file_id], params[:user_id].to_s)
  if (result.is_a? String) && result.start_with?("ERROR: ")
    session[:error] = result
  end
  redirect back
end

# Add a user to a file.
#
# @see Model#add_user
post("/user/add") do
  result = add_user(session[:login], params[:file_id], params[:username].to_s)
  if (result.is_a? String) && result.start_with?("ERROR: ")
    session[:error] = result
  end
  redirect back
end

# Resend confirmation email
#
# @see Model#send_confirmation_email
post("/user/resend_email") do
  user_info = get_all_user_info(session[:login])

  unless user_info.nil?
    session[:confirm_email] = send_confirmation_email(user_info["email"], config, user_info["username"], request.host_with_port)
  end

  redirect back
end

# Regesters a user and sends confirmation email
#
# @see Model#user_register
# @see Model#send_confirmation_email
post("/user/register") do
  digest = user_register(params[:password], params[:name], params[:email])

  if digest.start_with?("ERROR: ")
    session[:error] = digest[7..-1]
    redirect("/")
  else
    session[:login] = digest
  end

  session[:confirm_email] = send_confirmation_email(params[:email], config, params[:name], request.host_with_port)

  session[:name] = params[:name]
  session[:role] = "member"
  redirect("/")
end

# Logins a user and remembers their login information if the checkbox is checked
#
# @param [Integer] password, user password
# @param [Integer] name, username
# @param [Boolean] remember, if it should remember the login information
#
# @see Model#user_register
# @see Model#send_confirmation_email
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

# Clears the session making the user logout
post("/user/logout") do
  session.clear
  redirect back
end

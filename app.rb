# frozen_string_literal: true

require "slim"
require "sinatra"
require "sqlite3"
require "bcrypt"
require_relative "./model.rb"

enable :sessions

before do
  # for testing
  # session[:login] = "$2a$12$Wr1G1Y7elWcsdBPGJeUq0ut3AMsZZ/58jqhsC6Uxx2cz2Wn/wsMOS"
  # session[:name] = "hej"
  # session[:role] = "member"

  redirect("/") if request.path_info != "/" && !request.path_info.start_with?("/user/") && session[:login].nil?
end

get("/") do
  if session[:login].nil?
    # Not logged in redirects to the startpage
    slim(:start)
  else
    # logged in
    redirect("/files/view")
  end
end

get("/files/view") do
  files = get_files(session[:login])
  slim(:"files/view", locals: {name: session[:name], user_id: files[0], file_id: files[1]})
end

post("/files/create") do
  # to-do: Export to model.rb
  user_id = db.execute("SELECT id FROM users WHERE password_digest = ?", session[:login])[0]["id"]
  filename = params[:file][:filename]
  file = params[:file][:tempfile]
  path = "files/#{user_id}/#{filename}"
  public_file = 0
  if params[:public]
    path = "./public/" + path
    public_file = 1
  else
    path = "./private/" + path
  end

  Dir.mkdir "private/files/#{user_id}" unless Dir.exist?("private/files/#{user_id}")

  File.open(path, "w+") do |f|
    f.write(file.read)
  end
  db.execute("INSERT INTO files (date, path, public) VALUES (?, ?, ?);", Time.now.to_i, path, public_file)
  file_id = db.execute("SELECT id FROM files WHERE path = ?", path)[0]["id"]
  db.execute("INSERT INTO files_users (file_id, user_id) VALUES (?, ?);", file_id, user_id)
  category = db.execute("SELECT id FROM category WHERE name = ?", params[:file][:type])

  db.execute("INSERT INTO category (name) VALUES (?);", params[:file][:type]) if category == []

  category_id = db.execute("SELECT id FROM category WHERE name = ?", params[:file][:type])[0]["id"]

  db.execute("INSERT INTO category_files (cat_id, file_id) VALUES (?, ?);", category_id, file_id)
  redirect("/files/view")
end

post("/user/register") do
  session[:name] = params[:name]
  session[:role] = "member"
  session[:login] = user_register(params[:password], params[:name])
  redirect("/")
end

post("/user/login") do
  password = params[:password]
  name = params[:name]
  user_info = user_login(password, name)
  if user_info[:password_correct]
    session[:login] = user_info[:password_digest]
    session[:name] = name
    session[:role] = user_info[:role] == "admin" ? "admin" : "member"
  end
  redirect("/")
end

post("/user/logout") do
  session.clear
  redirect("/")
end

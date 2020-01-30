require "slim"
require "sinatra"
require "sqlite3"
require "bcrypt"

enable :sessions

db = SQLite3::Database.new("db/users.db")
db.results_as_hash = true

get("/") do
  if session[:login].nil?
    slim(:start)
  else
    user_id = db.execute("SELECT user_id FROM users WHERE password_digest = ?", params[:password])
    file_id = db.execute("SELECT file_id FROM file_users WHERE user_id = ?", user_id[0]["user_id"])
    slim(:"files/view", locals: {name: session[:name]})
  end
end

post("/user/register") do
  password = params[:password]
  name = params[:name]
  password_digest = BCrypt::Password.create(password)
  session[:login] = password_digest
  session[:name] = name
  begin
    db.execute("INSERT INTO users (username, password_digest, role) VALUES (?, ?, 'member')", name, password_digest)
  rescue StandardError => e
    p e
  end
  redirect("/")
end

post("/user/login") do
  password = params[:password]
  name = params[:name]
  password_digest = db.execute("SELECT password_digest,role FROM users WHERE username = ?", name)

  if password_digest[0]["role"] == "admin"
    session[:role] = "admin"
  else
    session[:role] = "member"
  end

  if password_digest != [] && BCrypt::Password.new(password_digest[0]["password_digest"]) == password
    session[:login] = password_digest[0]["password_digest"]
    session[:name] = name
  end
  redirect("/")
end

post("/user/logout") do
  session[:role] = "member"
  session[:login] = nil
  session[:name] = nil
  redirect("/")
end

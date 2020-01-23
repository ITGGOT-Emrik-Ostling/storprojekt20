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
    slim(:"files/view", locals: {name: session[:name]})
  end
end

post("/register") do
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

post("/login") do
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

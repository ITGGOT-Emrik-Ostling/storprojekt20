require "slim"
require "sinatra"
require "sqlite3"
require "bcrypt"

enable :sessions

db = SQLite3::Database.new("db/users.db")
db.results_as_hash = true

before do
  if request.path_info != "/" && !request.path_info.start_with?("/user/") && session[:login].nil?
    redirect("/")
  end
end


get("/") do
  if session[:login].nil?
    slim(:start)
  else
    redirect("/files/view")
  end
end

get("/files/view") do
  user_id = db.execute("SELECT id FROM users WHERE password_digest = ?", session[:login])
  file_id = db.execute("SELECT file_id FROM files_users WHERE user_id = ?", user_id[0]["id"])
  slim(:"files/view", locals: {name: session[:name], user_id: user_id, file_id: file_id})
end

post("/files/create") do
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

  unless Dir.exist?("private/files/#{user_id}")
    Dir.mkdir "private/files/#{user_id}"
  end

  File.open(path, "w+") do |f|
    f.write(file.read)
  end
  hmm = db.execute("INSERT INTO files (date, path, public) VALUES (?, ?, ?);", Time.now.to_i, path, public_file)
  p hmm
  # params[:file][:type]
  redirect("/files/view")
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

  session[:role] = password_digest[0]["role"] == "admin" ? "admin" : "member"

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

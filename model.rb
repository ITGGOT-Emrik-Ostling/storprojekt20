def db
  db = SQLite3::Database.new("db/users.db")
  db.results_as_hash = true
  return db
end

def get_files(password_digest)
  # files = db.execute("SELECT id, file_id
  # FROM (users
  #   INNER JOIN files_users ON users.id = files_users.user_id)
  # WHERE password_digest = ?", password_digest)
  # return files
  user_id = db.execute("SELECT id FROM users WHERE password_digest = ?", password_digest)
  file_id = db.execute("SELECT file_id FROM files_users WHERE user_id = ?", user_id[0]["id"])
  public_file_id = db.execute("SELECT id FROM files WHERE public = 1")
  return [user_id, file_id + public_file_id]
end

def user_register(password, name)
  password_digest = BCrypt::Password.create(password)
  begin
    db.execute("INSERT INTO users (username, password_digest, role) VALUES (?, ?, 'member')", name, password_digest)
  rescue => error
    p error
    # olagliga inloggningsuppgifter
  end
  return password_digest
end

def user_login(password, name)
  user_info = db.execute("SELECT password_digest,role FROM users WHERE username = ?", name)[0]

  password_correct = false
  if user_info != [] && BCrypt::Password.new(user_info["password_digest"]) == password
    password_correct = true
  end

  return {role: user_info["role"], password_correct: password_correct, password_digest: user_info["password_digest"]}
end

def file_upload()

end
# frozen_string_literal: true

def db
  db = SQLite3::Database.new("db/users.db")
  db.results_as_hash = true
  db
end

def get_user_id(password_digest)
  id = db.execute("SELECT id FROM users WHERE password_digest = ?", password_digest)
  if (id == []) || id.nil?
    return nil
  else
    return id[0]["id"]
  end
end

def get_file_ids(password_digest)
  user_id = get_user_id(password_digest)
  file_id = db.execute("SELECT file_id FROM files_users WHERE user_id = ?", user_id)
  # public_file_id = db.execute("SELECT id FROM files WHERE public = 1")
  # return file_id + public_file_id
  file_id
end

def array_of_hashes_to_array(hash_array)
  out = []
  if !hash_array.is_a?(Array)
    out << hash_array
  else
    hash_array.length.times do |iteration|
      out << hash_array[iteration].values[0]
    end
  end
  out
end

def get_files(file_ids)
  ids = array_of_hashes_to_array(file_ids)
  # if file_ids.length == 1
  #   ids = array_of_hashes_to_array(file_ids)
  # elsif file_ids.length == 2
  #   ids = array_of_hashes_to_array(file_ids[0]) + array_of_hashes_to_array(file_ids[1])
  # end

  ids = ids.to_s
  ids[0] = "("
  ids[-1] = ")"

  files = db.execute("SELECT * FROM files WHERE id IN #{ids}")
  public_files = db.execute("SELECT * FROM files WHERE public = 1")
  {files: files, public_files: public_files}
end

def user_register(password, name, email)
  password_digest = BCrypt::Password.create(password)
  begin
    p db.execute("INSERT INTO users (email, username, password_digest, role) VALUES (?, ?, ?, 'member')", email, name, password_digest)
  rescue
    return "ERROR: Username or Email is already taken, try to login"
  end
  password_digest
end

def user_login(password, name)
  user_info = db.execute("SELECT password_digest,role FROM users WHERE username = ?", name)[0]

  password_correct = false
  if !user_info.nil? && user_info != [] && BCrypt::Password.new(user_info["password_digest"]) == password
    password_correct = true
    return {role: user_info["role"], password_correct: password_correct, password_digest: user_info["password_digest"]}
  end

  {password_correct: password_correct}
end

def file_upload(password_digest, parentfile, publicfile)
  user_id = get_user_id(password_digest)
  filename = parentfile[:filename]
  file = parentfile[:tempfile]
  # path = "files/#{user_id}/#{filename}"
  path = "files/#{user_id}"
  public_file = 0

  if publicfile
    path = "public/" + path
    public_file = 1
  else
    path = "private/" + path
  end

  Dir.mkdir path unless Dir.exist?(path)

  path = "./#{path}/#{filename}"

  i = 1
  dotpos = 0
  while File.exist?(path)
    j = 1
    if dotpos == 0
      while path.length > j
        if path[-j] == "."
          dotpos = -j - 1
          break
        elsif path[-j] == "/" && j > 1
          dotpos = -1
          break
        end
        j += 1
      end
    end

    # Filen existerar, så den får ett nytt namn
    path = +path
    if i == 1
      path = path.insert(dotpos, ".#{i}")
    else
      path[dotpos - ((i - 1).to_s.length - 1)..dotpos] = i.to_s
    end
    i += 1
  end

  File.open(path, "wb") do |f| # wb is the shit, w+ is not good and corrupts everyhting
    f.write(file.read)
  end

  db.execute("INSERT INTO files (date, path, public) VALUES (?, ?, ?);", Time.now.to_i, path, public_file)
  file_id = db.execute("SELECT id FROM files WHERE path = ?", path)[0]["id"]
  db.execute("INSERT INTO files_users (file_id, user_id) VALUES (?, ?);", file_id, user_id)
  category = db.execute("SELECT id FROM category WHERE name = ?", parentfile[:type])

  if category == []
    db.execute("INSERT INTO category (name) VALUES (?);", parentfile[:type])
    category = db.execute("SELECT id FROM category WHERE name = ?", parentfile[:type])
  end

  db.execute("INSERT INTO category_files (cat_id, file_id) VALUES (?, ?);", category[0]["id"], file_id)
end

def delete_file(file_id, password_digest)
  db.execute()
end

def email_confirm(password_digest)
  db.execute("UPDATE users SET email_confirmed = 1 WHERE password_digest = ?;", password_digest)
end

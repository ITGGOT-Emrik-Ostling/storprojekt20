# frozen_string_literal: true

def db_connect
  db = SQLite3::Database.new("db/users.db")
  db.results_as_hash = true
  db
end

def get_user_id(password_digest)
  db = db_connect
  id = db.execute("SELECT id FROM users WHERE password_digest = ?", password_digest)
  if (id == []) || id.nil?
    nil
  else
    id[0]["id"]
  end
end

def get_file_ids(password_digest)
  db = db_connect
  user_id = get_user_id(password_digest)
  file_id = db.execute("SELECT file_id FROM files_users WHERE user_id = ?", user_id)
  # public_file_id = db.execute("SELECT id FROM files WHERE public = 1")
  # return file_id + public_file_id
  file_id
end

def array_of_hashes_to_array(hash_array)
  db = db_connect
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

# Slår ihop flera rader i en hash efter vad dupe är dublett
def merge_duplicates(array, merge, dupe)
  db = db_connect
  i = 0
  while i + 1 < array.length
    if array[i][dupe] == array[i + 1][dupe]
      # de ska slås ihop
      merge.each do |m|
        if array[i][m] != array[i + 1][m]
          if array[i][m].is_a?(String)
            array[i][m] = [array[i][m], array[i + 1][m]]
          elsif array[i][m].is_a?(Array)
            array[i][m] += array[i + 1][m]
          end
        end
      end
      array.delete_at(i + 1)
    else
      i += 1
    end
  end
  array
end

def get_files(ids = nil)
  db = db_connect
  sql_base = "SELECT files.*, category.category_name, files_users.user_id, users.username FROM ((((category_files
    INNER JOIN category ON category.id = category_files.cat_id)
    INNER JOIN files ON files.id = category_files.file_id)
    INNER JOIN files_users ON files_users.file_id = category_files.file_id)
    INNER JOIN users ON users.id == files_users.user_id)
    WHERE"
  files = if ids.nil?
    db.execute(sql_base + " public = 1")
  else
    db.execute(sql_base + " files.id IN #{ids}")
  end
  files = merge_duplicates(files, ["category_name", "username", "user_id"], "id")
  files
end

def get_all_files(file_ids)
  db = db_connect
  ids = array_of_hashes_to_array(file_ids)

  ids = ids.to_s
  ids[0] = "("
  ids[-1] = ")"

  public_files = get_files
  files = get_files(ids)
  {files: files, public_files: public_files}
end

def user_register(password, name, email)
  db = db_connect
  password_digest = BCrypt::Password.create(password)
  begin
    p db.execute("INSERT INTO users (email, username, password_digest, role) VALUES (?, ?, ?, 'member')", email, name, password_digest)
  rescue
    return "ERROR: Username or Email is already taken, try to login"
  end
  password_digest
end

def user_login(password, name)
  db = db_connect
  user_info = db.execute("SELECT password_digest,role FROM users WHERE username = ?", name)[0]

  password_correct = false
  if !user_info.nil? && user_info != [] && BCrypt::Password.new(user_info["password_digest"]) == password
    password_correct = true
    return {role: user_info["role"], password_correct: password_correct, password_digest: user_info["password_digest"]}
  end

  {password_correct: password_correct}
end

def file_upload(password_digest, parentfile, publicfile)
  db = db_connect
  if parentfile.nil?
    return "ERROR: please select a file you want to upload, lol"
  end
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

  categories = parentfile[:type].split("/")
  categories.each do |category|
    category_id = db.execute("SELECT id FROM category WHERE category_name = ?", category.chomp)
    p "kategorier problemet"
    p category
    p category_id
    if category_id == []
      p category_id == []
      db.execute("INSERT INTO category (category_name) VALUES (?);", category.chomp)
      category_id = db.execute("SELECT id FROM category WHERE category_name = ?", category)
    end

    db.execute("INSERT INTO category_files (cat_id, file_id) VALUES (?, ?);", category_id[0]["id"], file_id)
  end
end

def delete_file(file_id, password_digest)
  db = db_connect
  user_id = db.execute("SELECT user_id FROM files_users WHERE file_id = ?", file_id)
  p user_id
  if !user_id.nil? && user_id[0]["user_id"] == get_user_id(password_digest)
    file_path = db.execute("SELECT path FROM files WHERE id = ?", file_id)
    db.execute("DELETE FROM files_users WHERE file_id = ?", file_id)
    db.execute("DELETE FROM files WHERE id = ?", file_id)
    db.execute("DELETE FROM category_files WHERE file_id = ?", file_id)

    if !file_path.nil? && File.exist?(file_path[0]["path"])
      File.delete(file_path[0]["path"])
    else
      "ERROR: the file doesn't exist"
    end
  else
    "ERROR: you don't have permission to delete that file"
  end
end

def delete_category(password_digest, file_id, category_name)
  db = db_connect
  file_ids = db.execute("SELECT file_id FROM files_users WHERE user_id = ? AND file_id = ?", get_user_id(password_digest), file_id)
  if file_id.to_i == file_ids[0]["file_id"]
    category_id = db.execute("SELECT id FROM category WHERE category_name = ?", category_name)
    p category_name
    p category_id
    p file_id
    if category_id == [] || category_id.nil?
      return "ERROR: Category doesn't exist"
    end
    db.execute("DELETE FROM category_files WHERE cat_id = ? AND file_id = ?", category_id[0]["id"], file_id)
  else
    return "ERROR: Insufficient permissions"
  end
  nil
end

def email_confirm(password_digest)
  db = db_connect
  db.execute("UPDATE users SET email_confirmed = 1 WHERE password_digest = ?;", password_digest)
end

def email_status(password_digest)
  db = db_connect
  status = db.execute("SELECT email_confirmed FROM users WHERE password_digest = ?", password_digest)
  if (status == []) || status.nil?
    false
  else
    status[0]["email_confirmed"] == 1
  end
end

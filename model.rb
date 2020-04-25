# frozen_string_literal: true

#
# Handles
#
module Model
  # Connects to the database
  #
  # @return [SQLite3::Database] containing the database
  def db_connect
    db = SQLite3::Database.new("db/users.db")
    db.results_as_hash = true
    db
  end

  # Get a users id
  #
  # @param password_digest [String] the user's password hash
  #
  # @return [Integer, nil] with the user id
  def get_user_id(password_digest)
    db = db_connect
    id = db.execute("SELECT id FROM users WHERE password_digest = ?", password_digest)
    if (id == []) || id.nil?
      nil
    else
      id[0]["id"]
    end
  end

  # Get a all user info
  #
  # @param password_digest [String] the user's password hash
  #
  # @return [hash, nil] with the user id
  def get_all_user_info(password_digest)
    db = db_connect
    user_info = db.execute("SELECT * FROM users WHERE password_digest = ?", password_digest)
    if (user_info == []) || user_info.nil?
      nil
    else
      user_info[0]
    end
  end

  # Get all file ids belonging to a certain user
  #
  # @param password_digest [String] the user's password hash
  #
  # @return [Hash] containing all ids
  def get_file_ids(password_digest)
    db = db_connect
    user_id = get_user_id(password_digest)
    file_id = db.execute("SELECT file_id FROM files_users WHERE user_id = ?", user_id)
    # public_file_id = db.execute("SELECT id FROM files WHERE public = 1")
    # return file_id + public_file_id
    file_id
  end

  # Takes an array of hashes and takes all elements and put them in a one dimensional array
  #
  # @param hash_array [Array] a array with hashes
  #
  # @return [Array] containing all elements from the hashes
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

  # Merges multiple rows in a hash after where dupe is a dublette
  #
  # @param array [Array] a array
  # @param merge [Array] to merge array with
  # @param dupe [String] dublette to look for and merge
  #
  # @return [Array] with the array and merge merged to one array
  def merge_duplicates(array, merge, dupe)
    array.sort_by! { |elem| elem["id"] }
    i = 0
    while i + 1 < array.length
      if array[i][dupe] == array[i + 1][dupe]
        # should merge
        merge.each do |m|
          if array[i][m] != array[i + 1][m]
            if array[i][m].is_a?(Array) && !array[i][m].include?(array[i + 1][m])
              if array[i + 1][m].is_a?(Array)
                array[i][m] += array[i + 1][m]
              else
                array[i][m] << array[i + 1][m]
              end
            elsif !array[i][m].is_a?(Array) && !array[i + 1][m].is_a?(Array)
              array[i][m] = [array[i][m], array[i + 1][m]]
            elsif array[i + 1][m].is_a?(Array) && !array[i + 1][m].include?(array[i][m])
              array[i][m] = [array[i][m]] + array[i + 1][m]
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

  # get private or public files
  #
  # @param ids [Array] ids to look for if looking for private files
  #
  # @return [Array] with all the files as individual hashes
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

  # get both private and public files and makes sure ids are formatted correctly
  #
  # @param file_ids [Array] ids to look for
  #
  # @return [Hash] with public and private files as array with all their files as individual hashes
  def get_all_files(file_ids)
    ids = array_of_hashes_to_array(file_ids)

    ids = ids.to_s
    ids[0] = "("
    ids[-1] = ")"

    public_files = get_files
    files = get_files(ids)
    {files: files, public_files: public_files}
  end

  # Checks if the current user is allowed to access a private file
  #
  # @param [String] password_digest the user's password hash
  # @param [Integer] user_id the user id that uploaded the file
  # @param [Boolean] file_name is the files name
  #
  # @return [String] error if an error occured
  def user_can_access_private_file(password_digest, user_id, file_name)
    path = "./private/files/#{user_id}/#{file_name}"
    if File.exist?(path)
      current_user = get_user_id(password_digest)
      if current_user == user_id.to_i
        return true
      end
      db = db_connect
      file_info = db.execute("SELECT user_id FROM files INNER JOIN files_users ON files_users.file_id = files.id WHERE path = ? AND user_id = ?", path, current_user)

      if file_info == [] || file_info.nil?
        return "ERROR: Access denied"
      end

      if file_info[0]["user_id"] == current_user
        true
      else
        "ERROR: Unknown error"
      end
    else
      "ERROR: File doesn't exist"
    end
  end

  # get both private and public files and makes sure ids are formatted correctly
  #
  # @param password [String] user's password
  # @param name [String] user's username
  # @param email [String] user's email
  #
  # @return [String] containing the password digest
  # @return [String] containing a error if an error occurred
  def user_register(password, name, email)
    db = db_connect
    password_digest = BCrypt::Password.create(password)
    begin
      db.execute("INSERT INTO users (email, username, password_digest, role) VALUES (?, ?, ?, 'member')", email.chomp, name.chomp, password_digest.chomp)
    rescue
      return "ERROR: Username or Email is already taken, try to login"
    end
    password_digest
  end

  # Login the user with the password and username
  #
  # @param password [String] the user submitted password
  # @param name [String] the user's username
  #
  # @return [Hash] with additional information if password is correct
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

  # Send email to confirm email
  #
  # @param [String] mail_to user's email address
  # @param [Array] email_config all email settings
  # @param [String] name the username
  # @param [String] host the url of the website
  #
  # @return [String] generated key to match with key in email
  def send_confirmation_email(mail_to, email_config, name, host)
    Mail.defaults do
      delivery_method :smtp, {
        address: email_config["email_server"],
        port: 465,
        user_name: email_config["email_user"],
        password: email_config["email_password"],
        authentication: :login,
        ssl: true,
        openssl_verify_mode: "none"
      }
    end

    confirm_email_key = SecureRandom.urlsafe_base64

    Mail.new(
      to: mail_to.to_s,
      from: email_config["email_user"].to_s,
      subject: "Confirm your account at epic cloud site",
      body: "Welcome to OUR site #{name}, where we steal you're data and sell it for profit\nSounds good?\n\nClick here to erase your suffering (by reading this mail you accept all our terms and conditions which include but is not limited to giving us all your possession and everything you are)\nhttp://#{host}/user/confirm_email/#{confirm_email_key}\n\nThanks for all the fish (and your soul)!"
    ).deliver

    confirm_email_key
  end

  # Save the file in the database, makes sure there isn't any duplicates and save the file to disk
  #
  # @param [String] password_digest the user's password hash
  # @param [Array] parentfile file object returned by the fileupload form containing file information
  # @param [Boolean] publicfile is the file public
  #
  # @return [String] error if an error occured
  def file_upload(password_digest, parentfile, publicfile)
    db = db_connect
    if parentfile.nil?
      return "ERROR: Please select a file you want to upload, lol"
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
      if category_id == []
        db.execute("INSERT INTO category (category_name) VALUES (?);", category.chomp)
        category_id = db.execute("SELECT id FROM category WHERE category_name = ?", category.chomp)
      end

      db.execute("INSERT INTO category_files (cat_id, file_id) VALUES (?, ?);", category_id[0]["id"], file_id)
    end
  end

  # Delete a file
  #
  # @param [Integer] file_id the id of the file
  # @param [String] password_digest the user's password hash
  #
  # @return [String] error message if an error occurred
  def delete_file(file_id, password_digest)
    db = db_connect
    user_id = db.execute("SELECT user_id FROM files_users WHERE file_id = ?", file_id)

    if !user_id.nil? && user_id != [] && user_id[0]["user_id"] == get_user_id(password_digest)
      file_path = db.execute("SELECT path FROM files WHERE id = ?", file_id)
      db.execute("DELETE FROM files_users WHERE file_id = ?", file_id)
      db.execute("DELETE FROM files WHERE id = ?", file_id)
      db.execute("DELETE FROM category_files WHERE file_id = ?", file_id)

      if !file_path.nil? && File.exist?(file_path[0]["path"])
        File.delete(file_path[0]["path"])
      else
        "ERROR: The file doesn't exist"
      end
    else
      "ERROR: You don't have permission to delete that file"
    end
  end

  # Deletes a category
  #
  # @param [String] password_digest the user's password hash
  # @param [Integer] file_id the id of the file
  # @param [String] category_name to delete
  #
  # @return [String, nil] error message if error occurred otherwise nil
  def delete_category(password_digest, file_id, category_name)
    db = db_connect
    file_ids = db.execute("SELECT file_id FROM files_users WHERE user_id = ? AND file_id = ?", get_user_id(password_digest), file_id)
    if file_id.to_i == file_ids[0]["file_id"]
      category_id = db.execute("SELECT id FROM category WHERE category_name = ?", category_name)
      if category_id == [] || category_id.nil?
        return "ERROR: Category doesn't exist"
      end
      db.execute("DELETE FROM category_files WHERE cat_id = ? AND file_id = ?", category_id[0]["id"], file_id)
    else
      return "ERROR: Insufficient permissions"
    end
    nil
  end

  # Add a category to a already existing file
  #
  # @param [String] password_digest the user's password hash
  # @param [Integer] file_id the id of the file
  # @param [String] category_name to add
  #
  # @return [String, nil] error message if error occurred otherwise nil
  def add_category(password_digest, file_id, category_name)
    db = db_connect
    file_ids = db.execute("SELECT file_id FROM files_users WHERE user_id = ? AND file_id = ?", get_user_id(password_digest), file_id)
    if file_id.to_i == file_ids[0]["file_id"]
      category_id = db.execute("SELECT id FROM category WHERE category_name = ?", category_name)
      if category_id == []
        db.execute("INSERT INTO category (category_name) VALUES (?);", category_name.chomp)
        category_id = db.execute("SELECT id FROM category WHERE category_name = ?", category_name.chomp)
      end

      duplicate_control = db.execute("SELECT file_id FROM category_files WHERE file_id = ? AND cat_id = ?", file_id.to_i, category_id)

      if duplicate_control == []
        db.execute("INSERT INTO category_files (cat_id, file_id) VALUES (?, ?);", category_id[0]["id"], file_id)
      else
        return "ERROR: Category is already applied"
      end
    else
      return "ERROR: Insufficient permissions"
    end
    nil
  end

  # Deletes a user from a file
  #
  # @param [String] password_digest the user's password hash
  # @param [Integer] file_id the id of the file
  # @param [String] username to delete
  #
  # @return [String, nil] error message if error occurred otherwise nil
  def delete_user(password_digest, file_id, user_id)
    db = db_connect
    file_ids = db.execute("SELECT file_id FROM files_users WHERE user_id = ? AND file_id = ?", get_user_id(password_digest), file_id)
    if file_id.to_i == file_ids[0]["file_id"]
      duplicate_control = db.execute("SELECT user_id FROM files_users WHERE file_id = ? AND user_id = ?", file_id, user_id)

      if duplicate_control == [] || duplicate_control.nil?
        return "ERROR: User doesn't exist"
      end

      db.execute("DELETE FROM files_users WHERE user_id = ? AND file_id = ?", user_id, file_id)
    else
      return "ERROR: Insufficient permissions"
    end
    nil
  end

  # Add a user to a already existing file
  #
  # @param [String] password_digest the user's password hash
  # @param [Integer] file_id the id of the file
  # @param [String] username to add
  #
  # @return [String, nil] error message if error occurred otherwise nil
  def add_user(password_digest, file_id, username)
    db = db_connect
    file_ids = db.execute("SELECT file_id FROM files_users WHERE user_id = ? AND file_id = ?", get_user_id(password_digest), file_id)
    if file_id.to_i == file_ids[0]["file_id"]
      user_id = db.execute("SELECT id FROM users WHERE username = ?", username.chomp)

      if user_id == [] || user_id.nil?
        return "ERROR: User doesn't exist"
      end

      duplicate_control = db.execute("SELECT user_id FROM files_users WHERE file_id = ? AND user_id = ?", file_id.to_i, user_id[0]["id"])

      if duplicate_control == [] || duplicate_control.nil?
        db.execute("INSERT INTO files_users (user_id, file_id) VALUES (?, ?);", user_id[0]["id"], file_id.to_i)
      else
        return "ERROR: User already owns this file"
      end
    else
      return "ERROR: Insufficient permissions"
    end
    nil
  end

  # Confirms the email
  #
  # @param [String] password_digest the user's password hash
  def email_confirm(password_digest)
    db = db_connect
    db.execute("UPDATE users SET email_confirmed = 1 WHERE password_digest = ?;", password_digest)
  end

  # Checks if email is confirmed
  #
  # @param [String] password_digest the user's password hash
  #
  # @return [Boolean] is the email confirmed
  def email_status(password_digest)
    db = db_connect
    status = db.execute("SELECT email_confirmed FROM users WHERE password_digest = ?", password_digest)
    if (status == []) || status.nil?
      false
    else
      status[0]["email_confirmed"] == 1
    end
  end
end

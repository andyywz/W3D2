require 'singleton'
require 'sqlite3'

class QuestionsDatabase < SQLite3::Database
  include Singleton

  def initialize
    super("user_questions.db")

    self.results_as_hash = true
    self.type_translation = true
  end
end

class User
  attr_accessor :fname, :lname
  attr_reader :user_id

  def initialize(options = {})
    @fname = options['fname']
    @lname = options['lname']
    # @user_id = options['user_id']
    @user_id = nil
  end

  def self.find_by_name(fname, lname)
    query = <<-SQL
      SELECT *
      FROM users
      WHERE users.fname = ? AND users.lname = ?
    SQL

    users_data = QuestionsDatabase.instance.execute(query, fname, lname)
    users_data.empty? ? nil : User.new_with_id(users_data[0])
  end

  def self.find_by_id(id)
    query = <<-SQL
      SELECT *
      FROM users
      WHERE users.user_id = ?
    SQL

    users_data = QuestionsDatabase.instance.execute(query, id)
    users_data.empty? ? nil : User.new_with_id(users_data[0])
  end

  def authored_questions
    Question.find_by_author_id(@user_id)
  end

  def authored_replies
    Reply.find_by_user_id(@user_id)
  end

  def followed_questions
    QuestionFollower.followed_questions_for_user_id(@user_id)
  end

  def liked_questions
    QuestionLike.liked_questions_for_user_id(@user_id)
  end

  def average_karma
    query = <<-SQL
      SELECT
        CASE WHEN COUNT(x.q_id) = 0
          THEN 0
        ELSE
          CAST(SUM(x.lc) AS float)/COUNT(x.q_id)
        END
        AS avg
      FROM
       (SELECT COUNT(ql.user_id) AS lc, q.question_id AS q_id
        FROM questions AS q LEFT JOIN question_likes AS ql
        ON ql.question_id = q.question_id
        WHERE q.author_id = 1
        GROUP BY ql.question_id) AS x
    SQL

    likes_data = QuestionsDatabase.instance.execute(query, @user_id)

    likes_data.empty? ? nil : likes_data[0]['avg']
  end

  def save
    if @user_id.nil?
      query = <<-SQL
        INSERT INTO users ('fname','lname')
        VALUES (?, ?)
      SQL
      QuestionsDatabase.instance.execute(query, @fname, @lname)
      @user_id = QuestionsDatabase.instance.last_insert_row_id
    else
      query = <<-SQL
        UPDATE users
          SET fname = ?, lname = ?
          WHERE user_id = ?
      SQL
      QuestionsDatabase.instance.execute(query, @fname, @lname, @user_id)
    end
  end

  private

  def user_id=(user_id)
    @user_id = user_id
  end

  def self.new_with_id(user = {})
    new_user = self.new(user)
    new_user.send :user_id=, user['user_id']
    new_user
  end
end

class Question
  attr_accessor :title, :body, :author_id, :question_id

  def initialize(options = {})
    @question_id = nil
    @title = options['title']
    @body = options['body']
    @author_id = options['author_id']
  end

  def self.find_by_author_id(author_id)
    query = <<-SQL
      SELECT *
      FROM questions
      WHERE questions.author_id = ?
    SQL

    questions_data = QuestionsDatabase.instance.execute(query, author_id)

    return nil if questions_data.empty?

    questions_data.map {|x| Question.new(x)}
  end

  def self.most_followed(n)
    QuestionFollower.most_followed_questions(n)
  end

  def self.most_liked(n)
    QuestionLike.most_liked_questions(n)
  end

  def author
    query = <<-SQL
      SELECT author_id
      FROM questions
      WHERE questions.author_id = ?
    SQL

    questions_data = QuestionsDatabase.instance.execute(query, @author_id)

    questions_data.empty? ? nil : User.find_by_id(questions_data[0]['author_id'])
  end

  def replies
    Reply.find_by_question_id(@question_id)
  end

  def followers
    QuestionFollower.followers_for_question_id(@question_id)
  end

  def likers
    QuestionLike.likers_for_question_id(@question_id)
  end

  def num_likes
    QuestionLike.num_likes_for_question_id(@question_id)
  end

  def save
    if @question_id.nil?
      query = <<-SQL
        INSERT INTO questions ('title','body', 'author_id')
        VALUES (?, ?, ?)
      SQL
      QuestionsDatabase.instance.execute(query, @title, @body, @author_id)
      @question_id = QuestionsDatabase.instance.last_insert_row_id
    else
      query = <<-SQL
        UPDATE questions
          SET title = ?, body = ?
          WHERE question_id = ?
      SQL
      QuestionsDatabase.instance.execute(query, @title, @body, @question_id)
    end
  end

  private

  def question_id=(question_id)
    @question_id = question_id
  end

  def self.new_with_id(question = {})
    new_question = self.new(question)
    new_question.send :question_id=, question['question_id']
    new_question
  end

end

class Reply
  attr_accessor :reply
  attr_reader :id

  def initialize(options = {})
    @id = nil
    @reply = options['reply']
    @author_id = options['author_id']
    @question_id = options['question_id']
    @parent_id = options['parent_id']
  end

  def self.find_by_user_id(user_id)
    query = <<-SQL
      SELECT *
      FROM replies
      WHERE replies.author_id = ?
    SQL

    replies_data = QuestionsDatabase.instance.execute(query, user_id)

    return nil if replies_data.empty?

    replies_data.map {|x| Reply.new_with_id(x)}
  end

  def self.find_by_question_id(question_id)
    query = <<-SQL
      SELECT *
      FROM replies
      WHERE replies.question_id = ?
    SQL

    replies_data = QuestionsDatabase.instance.execute(query, question_id)

    return nil if replies_data.empty?

    replies_data.map {|x| Reply.new_with_id(x)}
  end

  def author
    query = <<-SQL
      SELECT author_id
      FROM replies
      WHERE replies.author_id = ?
    SQL

    replies_data = QuestionsDatabase.instance.execute(query, @author_id)

    replies_data.empty? ? nil : User.find_by_id(replies_data[0]['author_id'])
  end

  def question
    query = <<-SQL
      SELECT *
      FROM questions
      WHERE questions.question_id = ?
    SQL

    question_data = QuestionsDatabase.instance.execute(query, @question_id)

    question_data.empty? ? nil : Question.new(question_data[0])
  end

  def parent_reply
    query = <<-SQL
      SELECT *
      FROM replies
      WHERE replies.id = ?
    SQL

    replies_data = QuestionsDatabase.instance.execute(query, @parent_id)

    replies_data.empty? ? nil : Reply.new_with_id(replies_data[0])
  end

  def child_replies
    query = <<-SQL
      SELECT *
      FROM replies
      WHERE replies.parent_id = ?
    SQL

    replies_data = QuestionsDatabase.instance.execute(query, @id)

    return nil if replies_data.empty?

    replies_data.map {|x| Reply.new_with_id(x)}
  end

  def save
    if @id.nil?
      query = <<-SQL
        INSERT INTO replies ('reply','author_id','question_id','parent_id')
        VALUES (?, ?, ?, ?)
      SQL
      QuestionsDatabase.instance.execute(query, @reply, @author_id, @question_id, @parent_id)
      @id = QuestionsDatabase.instance.last_insert_row_id
    else
      query = <<-SQL
        UPDATE replies
          SET reply = ?
          WHERE id = ?
      SQL
      QuestionsDatabase.instance.execute(query, @reply, @id)
    end
  end

  private

  def id=(id)
    @id = id
  end

  def self.new_with_id(reply = {})
    new_reply = self.new(reply)
    new_reply.send :id=, reply['id']
    new_reply
  end
end

class QuestionFollower
  def initialize(options = {})
    @id = options['id']
    @question_id = options['question_id']
    @user_id = options['user_id']
  end

  def self.followers_for_question_id(question_id)
    # Join question_followers with questions on question_id
    query = <<-SQL
      SELECT u.*
      FROM question_followers AS qf JOIN users AS u
      ON (qf.user_id = u.user_id)
      WHERE qf.question_id = ?
    SQL

    followers_data = QuestionsDatabase.instance.execute(query, question_id)

    return nil if followers_data.empty?

    followers_data.map {|x| User.new_with_id(x)}
  end

  def self.followed_questions_for_user_id(user_id)
    query = <<-SQL
      SELECT q.*
      FROM question_followers AS qf JOIN questions AS q
      ON qf.question_id = q.question_id
      WHERE qf.user_id = ?
    SQL

    questions_data = QuestionsDatabase.instance.execute(query, user_id)

    return nil if questions_data.empty?

    questions_data.map {|x| Question.new(x)}
  end

  def self.most_followed_questions(n)
    query = <<-SQL
      SELECT q.*
      FROM question_followers AS qf JOIN questions AS q
      ON qf.question_id = q.question_id
      GROUP BY qf.question_id
      ORDER BY COUNT(qf.user_id) DESC
      LIMIT ?
    SQL

    questions_data = QuestionsDatabase.instance.execute(query, n)

    return nil if questions_data.empty?

    questions_data.map {|x| Question.new(x)}
  end
end

class QuestionLike
  def initialize(options = {})
    @question_id = options['question_id']
    @user_id = options['user_id']
  end

  def self.likers_for_question_id(question_id)
    query = <<-SQL
      SELECT u.*
      FROM users AS u JOIN (
        SELECT ql.*
        FROM question_likes AS ql JOIN questions AS q
        ON ql.question_id = q.question_id
        WHERE ql.question_id = ?
      ) AS x
      ON u.user_id = x.user_id
    SQL

    users_data = QuestionsDatabase.instance.execute(query, question_id)

    return nil if users_data.empty?

    users_data.map {|x| User.new_with_id(x)}
  end

  def self.num_likes_for_question_id(question_id)
    query = <<-SQL
      SELECT COUNT(user_id) AS num
      FROM question_likes AS ql
      WHERE ql.question_id = ?
      GROUP BY ql.question_id
    SQL

    likes_data = QuestionsDatabase.instance.execute(query, question_id)

    likes_data.empty? ? nil : likes_data[0]['num']
  end

  def self.liked_questions_for_user_id(user_id)
    query = <<-SQL
      SELECT q.*
      FROM questions AS q JOIN (
        SELECT ql.*
        FROM question_likes AS ql JOIN users AS u
        ON ql.user_id = u.user_id
        WHERE ql.user_id = ?
      ) AS x
      ON q.question_id = x.question_id
    SQL

    questions_data = QuestionsDatabase.instance.execute(query, user_id)

    return nil if questions_data.empty?

    questions_data.map {|x| Question.new(x)}
  end

  def self.most_liked_questions(n)
    query = <<-SQL
      SELECT q.*
      FROM question_likes AS ql JOIN questions AS q
      ON ql.question_id = q.question_id
      GROUP BY ql.question_id
      ORDER BY COUNT(ql.user_id) DESC
      LIMIT ?
    SQL

    questions_data = QuestionsDatabase.instance.execute(query, n)

    return nil if questions_data.empty?

    questions_data.map {|x| Question.new(x)}
  end
end

class Tag
  def self.most_popular
    query = <<-SQL
    SELECT t.tag,
      z.title, z.body, z.author_id, z.likes
    FROM tags AS t JOIN(
      SELECT
        qt.tag_id AS tag_id,
        y.title AS title,
        y.body AS body,
        y.author_id AS author_id,
        MAX(y.likes) AS likes
      FROM question_tags AS qt JOIN
        (SELECT q.*, COUNT(ql.user_id) AS likes
        FROM question_likes AS ql JOIN questions AS q
        ON ql.question_id = q.question_id
        GROUP BY ql.question_id
        ORDER BY COUNT(ql.user_id) DESC) AS y
      ON qt.question_id = y.question_id
      GROUP BY qt.tag_id) AS z
      ON t.tag_id = z.tag_id
    SQL

    QuestionsDatabase.instance.execute(query)
  end
end

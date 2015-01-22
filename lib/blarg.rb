require "blarg/version"
require 'pry'
require 'camping'

# NOTE: BLOG_REPO has to end with a slash/.
BLOG_REPO = '/Users/brit/projects/improvedmeans/'

Camping.goes :Blarg

module Blarg
  module Models
    class Post < Base
      has_many :post_tags
      has_many :tags, through: :post_tags
    end

    class Tag < Base
      has_many :post_tags
      has_many :posts, through: :post_tags
    end

    class PostTag < Base
      belongs_to :post
      belongs_to :tag
    end

    class InitializeDatabase < V 1.0
      def self.up
        create_table Post.table_name do |t|
          t.string :title
          t.string :tags
          t.string :format
          t.datetime :written
          t.text :text
        end
      end

      def self.down
        drop_table Post.table_name
      end
    end

    class RenameWrittenToDate < V 1.1
      def self.up
        rename_column Post.table_name, :written, :date
      end

      def self.down
        rename_column Post.table_name, :date, :written
      end
    end

    class AddTagsTable < V 1.2
      def self.up
        create_table Tag.table_name do |t|
          t.string :name, uniqueness: true
          t.timestamps
        end
      end

      def self.down
        drop_table Tag.table_name
      end
    end

    class AddPostTagTable < V 1.3
      def self.up
        create_table PostTag.table_name do |t|
          t.integer :post_id, index: true
          t.integer :tag_id, index: true
        end
      end

      def self.down
        drop_table Tagging.table_name
      end
    end

    class FillPostTags < V 1.4
      def self.up
        Post.find_each do |post|
          post.tags.each do |t|
            tag = Tag.find_or_create_by(:name => t)
            PostTag.create(:post_id => post.id, :tag_id => tag.id)
          end
        end
      end

      def self.down
        raise ActiveRecord::IrreversibleMigration
      end
    end

    class RemoveTagsColumnFromPosts < V 1.5
      def self.up
        remove_column Post.table_name, :tags
      end

      def self.down
        add_column Post.table_name, :tags, :string
      end
    end
  end
end

module Promptable
  def prompt(question, validator, error_msg, clear: nil)
    `clear` if clear
    puts "\n#{question}\n"
    result = $stdin.gets.chomp
    until result =~ validator
      puts "\n#{error_msg}\n"
      result = $stdin.gets.chomp
    end
    puts
    result
  end
end

class PostImporter
  include Enumerable
  include Promptable

  def initialize(posts_dir)
    @posts_dir = posts_dir
    choices = {}
    self.each_with_index do |post, i|
      choices[i+1] = post
    end
    @choices = choices
  end

  # NOTE: Trailing slash matters here.
  def each
    Dir.glob(@posts_dir + '*.post').each { |post| yield post }
  end

  def parse_post(file)
    result = {}
    File.open(file, 'r') do |f|
      result = parse_header(f)
      result[:text] = f.read
      result[:date] = DateTime.parse(result[:date])
      result[:tags] = result[:tags].split(', ')
    end
    result
  end

  def choose_post
    @choices.each do |i, post|
      puts "(#{i}) -- #{File.basename(post)}"
    end
    result = prompt("Which post would you like to import from your previous blog?",
                    /^#{@choices.keys.join('|')}$/,
                    "Please choose one of the listed numeric options.")
    path = @choices[result.to_i]
    parse_post(path)
  end

  private
  def marker?(line)
    line.chomp == ';;;;;'
  end

  def parse_header(fd)
    result = {}
    unless marker?(fd.readline)
      raise "The file '#{file}' does not have a valid header."
    end
    line = fd.readline
    until marker?(line)
      key, val = parse_metadata(line)
      result[key.to_sym] = val
      line = fd.readline
    end
    result
  end

  def parse_metadata(line)
    matcher = /^([a-zA-Z]+):\s+(.*)$/
    matches = line.match(matcher)
    return matches[1], matches[2]
  end
end

class BlogApp
  include Promptable

  def initialize
    @importer = PostImporter.new BLOG_REPO
  end

  def run
    puts "Hello there. Welcome to your personal blaaaarg!"
    # TODO: Have choose method for post screen or index screen.
    post_screen
  end

  def self.quit_handler
    puts "Thanks for blarging! Goodbye!"
    exit
  end

  private
  def import_post
    choice = prompt("Would you like to import a post? (yes/y, no/n, all)",
                  /^y|yes|n|no|all$/, "Please choose 'y', 'yes', 'n', 'no', or 'all'.")
    if choice == 'all'
      @importer.each do |p|
        opts = @importer.parse_post(p)
        tags = opts.delete(:tags)
        post = Blarg::Models::Post.create(opts)
        tags.each do |t|
          post.tags.create(:name => t)
        end
      end
    elsif ['y','yes'].include?(choice)
      opts = @importer.choose_post
      Blarg::Models::Post.create(opts)
    else
      puts "Your posts are imported. Thanks for stopping by!"
      BlogApp.quit_handler
    end
  end

  def post_screen
    message = "Would you like to (1) write a new post, (2) import a post from another blog, (3) find an existing post, or (QUIT)?"
    choice = prompt(message, /^([123]|QUIT)$/, "Please choose 1, 2, 3, or QUIT.", clear: true)
    case choice.to_i
    when 1
      add_post
    when 2
      import_post
    when 3
      # TODO: We might want to edit or delete a post that we find.
      find_post
    else
      BlogApp.quit_handler
    end
  end

  def index_screen
    message = "Would you like to (1) view indexes by date, (2) view indexes by tag, or (QUIT)?"
    choice = prompt(message, /^([12]|QUIT)$/, "Please choose 1, 2, or QUIT.", clear: true)
    case choice.to_i
    when 1
      view_date_index
    when 2
      view_tag_index
    else
      BlogApp.quit_handler
    end
  end
end

def Blarg.create
  Blarg::Models.create_schema
end

def top_months(n)
  result = Hash.new(0)
  Blarg::Models::Post.find_each do |post|
    result[post.date.month] += 1
  end
  #result.sort_by { || }
end

def top_months(n)
  sqlite_month = "strftime('%y-%m', date)"
  grouped = Blarg::Models::Post.select(sqlite_month).group(sqlite_month)
  ordered = grouped.count.sort_by { |k, v| -v}.to_h
  ordered.first(n).each do |m, posts|
    puts "Blogged #{posts} times in #{m}"
  end
end

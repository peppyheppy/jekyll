# Quickly hacked together my Michael Ivey
# Based on mt.rb by Nick Gerakines, open source and publically
# available under the MIT license. Use this module at your own risk.

require 'rubygems'
require 'sequel'
require 'fastercsv'
require 'fileutils'
require File.join(File.dirname(__FILE__),"csv.rb")

# NOTE: This converter requires Sequel and the MySQL gems.
# The MySQL gem can be difficult to install on OS X. Once you have MySQL
# installed, running the following commands should work:
# $ sudo gem install sequel
# $ sudo gem install mysql -- --with-mysql-config=/usr/local/mysql/bin/mysql_config

module Jekyll
  module Mephisto
    #Accepts a hash with database config variables, exports mephisto posts into a csv
    #export PGPASSWORD if you must
    DEFAULT_USER_ID = 1

    def self.postgres(c)
      sql = <<-SQL
      BEGIN;
      CREATE TEMP TABLE jekyll AS
        SELECT title, permalink, body, published_at, filter FROM contents
        WHERE user_id IN (%s) AND type = 'Article' ORDER BY published_at;
      COPY jekyll TO STDOUT WITH CSV HEADER;
      ROLLBACK;
      SQL
      command = %Q(psql -h #{c[:host] || "localhost"} -c "#{sql.strip}" #{c[:database]} #{c[:username]} -o #{c[:filename] || "posts.csv"})
      puts command
      `#{command}`
      CSV.process
    end

    # This query will pull blog posts from all entries across all blogs. If
    # you've got unpublished, deleted or otherwise hidden posts please sift
    # through the created posts to make sure nothing is accidently published.
    ARTICLE_QUERY = <<-SQL
      SELECT id,
              permalink,
              body,
              published_at,
              title,
              filter,
              comments_count
       FROM contents
       WHERE user_id = 2 AND
             type = 'Article' AND
             published_at IS NOT NULL
       ORDER BY published_at
    SQL

    ARTICLE_TAGS_QUERY = <<-SQL
      SELECT LOWER(tags.name) AS name
      FROM tags
      JOIN taggings ON taggings.tag_id = tags.id
      WHERE taggings.taggable_type = 'Content' AND
            taggings.taggable_id = %s
    SQL

    ARTICLE_COMMENTS_QUERY = <<-SQL
      SELECT title,
             body,
             author,
             author_url,
             author_email,
             author_ip,
             published_at,
             filter
      FROM contents
      WHERE article_id = %s
      ORDER BY published_at
    SQL

    def self.process(dbname, user, pass, host = 'localhost')
      db = Sequel.mysql(dbname, :user => user,
                                :password => pass,
                                :host => host,
                                :encoding => 'utf8')

      FileUtils.mkdir_p "_posts"

      db[(ARTICLE_QUERY % (ENV['USER_IDS'] || DEFAULT_USER_ID))].each do |post|
        title = post[:title]
        slug = post[:permalink]
        date = post[:published_at]
        content = post[:body]

        comments = []
        db[(ARTICLE_COMMENTS_QUERY % post[:id])].each do |comment|
          comments << {
            title: comment[:title],
            body: comment[:body].to_s,
            name: comment[:author],
            email: comment[:author_email],
            ip: comment[:author_ip],
            published_at: comment[:published_at],
          }
        end

        tags = []
        db[(ARTICLE_TAGS_QUERY % post[:id])].each do |tag|
          tags << tag
        end

        filter = post[:filter].gsub('_filter','').strip
        name = [date.year, date.day, date.month, slug].join('-') + ".#{filter.size > 0 ? filter : 'html'}"

        data = {
           'mt_id' => post[:id],
           'layout' => 'post',
           'title' => title.to_s,
           'tags' => tags,
           'comments' => comments,
         }.delete_if { |k,v| v.nil? || v == ''}.to_yaml

        File.open("_posts/#{name}", "w") do |f|
          f.puts data
          f.puts "---"
          f.puts content
        end
      end

    end
  end
end

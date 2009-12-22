#!/usr/bin/ruby -KU

require 'rubygems'
require 'sinatra'   # the web framework
require 'haml'      # html abstraction library
require 'wowdb'     # my wowdb.rb file


# Items in the configure block are executed once at startup.
configure do
  
  # set up an in-memory database
  db = Sequel.sqlite
  
  # this line defines an options.db variable
  set :db, db
  
  # create a new instance and migrate the db (but doesn't insert the example character)
  wowdb = WoWDB.new("Sedawk", "Sargeras", db)
  wowdb.create_database
end

# Generates and executes a SQL file to insert a character into the db
get '/insert/*-*.sql' do
  content_type 'text/plain', :charset => 'utf-8'
  
  name, server = params[:splat]
  
  wowdb = WoWDB.new(name, server, options.db)
  wowdb.create_database
  wowdb.generate_insert_statements!
end

# Renders the character listing page
get '/char/:name-:server' do
  content_type 'text/html', :charset => 'utf-8'
  
  name = params[:name]
  server = params[:server]

  @character = WoWDB.character_sheet(name, server, options.db)
  @items = WoWDB.item_list(name, server, options.db)
  
  haml :character
end

# Renders the guild listing page
get '/guild/*-*' do
  content_type 'text/html', :charset => 'utf-8'
  
  @realm, @server = params[:splat]

  @characters = WoWDB.guild_listing(@realm, @server, options.db)
  
  haml :guild
end

# the catch-all route
get '/?*' do
  
  @character_list = WoWDB.character_list(options.db)
  
  @character_list = nil if @character_list == []
  
  haml :index
end

# this block renders in case of an error
error do
  content_type 'text/html'
  haml :index
end


__END__
@@ layout
!!! 1.1
%html
  %head
    %title WoWDB
    %link{:rel => 'stylesheet', :href => 'http://www.w3.org/StyleSheets/Core/Midnight', :type => 'text/css'}
    %script{:src => 'http://www.wowhead.com/widgets/power.js'}
  %body
    %h1
      WoWDB
    #err.warning= env['sinatra.error']
    = yield
    #footer
      %small &copy; DM

@@ index
- unless @character_list.nil?
  The database currently contains:
  %ul
  - @character_list.each do |char, realm|
    %li
      %a{:href => "/char/#{char}-#{realm}"}>= "#{char}-#{realm}"
%br
URLs of this form dynamically generate (and execute) the SQL insert statements:
%ul
  %li
    %a{:href => '/insert/Sedawk-Sargeras.sql'}>= 'http://wowdb.heroku.com/insert/Sedawk-Sargeras.sql'
  %li
    %a{:href => '/insert/Bribbomir-Mannoroth.sql'}>= 'http://wowdb.heroku.com/insert/Bribbomir-Mannoroth.sql'
  %li
    %a{:href => '/insert/Onomatopeea-Sargeras.sql'}>= 'http://wowdb.heroku.com/insert/Onomatopeea-Sargeras.sql'
  %li
    Any others should work too. Reload this page once you've added a character to browse the DB.
Still broken:
%ul
  %li
    Never figured out where the Wowr API stores secondary spec.
  %li
    Never found a way to map an enchant id to enchant name.
      

@@ character
- if @character
  %h2
    = [@character[:name], @character[:realm]].join("-")
  %p
    Class:
    = @character[:class]
    %br
    Spec:
    = @character[:mspec]
    %br
    Guild: 
    %a{:href => "/guild/#{@character[:guild]}-#{@character[:realm]}"}>= "#{@character[:guild]}"
- if @items != []
  %h3
    Items:
  %ul
  - @items.each do |i|
    %li
      Name: 
      %a{:href => "http://www.wowhead.com/?item=#{i[:id]}"}>= "#{i[:item]}"
      %br
      ilvl: 
      = i[:ilvl]
      - unless i[:gem] == ""
        %br
        Gem: 
        %a{:href => "http://www.wowhead.com/?item=#{i[:geid]}"}>= "#{i[:gem]}"
      - unless i[:eid] == ""
        %br
        Enchant: 
        = i[:eid]
      - unless i[:monster] == ""
        %br
        Dropped by: 
        = i[:monster]
      - unless i[:raid] == ""
        %br
        In: 
        = i[:raid]
%br

@@ guild
%h2
  = @name
%h3
  = @realm
- if @characters
  %ul
  - @characters.each do |c|
    %li
      %a{:href => "/char/#{c[:name]}-#{@realm}"}>= "#{c[:name]}"
%br